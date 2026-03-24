import base64
import sys
import json
import functions_framework
import math
from google.cloud import netapp_v1

# Percentage of the volume capacity to increase
capacity_to_increase = 20

# Percentage of free capacity to abort the resize operation
free_capacity_threshold = 20

def calculate_capacity(volume_capacity, total_storage_pool_capacity, used_storage_pool_capacity, percentage):
	available_storage_pool_capacity = total_storage_pool_capacity - used_storage_pool_capacity
	increase_capacity = math.ceil(volume_capacity * (percentage / 100))

	if increase_capacity > available_storage_pool_capacity:
		total_storage_pool_capacity += increase_capacity

	volume_capacity += increase_capacity

	return volume_capacity, total_storage_pool_capacity

# Triggered from a message on a Cloud Pub/Sub topic.
@functions_framework.cloud_event
def netapp_volumes_autogrow(cloud_event):

	print("A NetApp Volumes capacity event has triggered the autogrow function.")
	message = base64.b64decode(cloud_event.data["message"]["data"]).decode()
	json_message = json.loads(message)

	# Manage the status of the alert
	state = json_message.get("incident", {}).get("state")
	if state == "closed":
		print("Incident state is 'closed'. Skipping the resize operation.")
		return

	myregion = json_message["incident"]["resource"]["labels"]["location"]
	myvolume = json_message["incident"]["resource"]["labels"]["name"]
	myproject = json_message["incident"]["resource"]["labels"]["resource_container"]

	# Create a client to get the volume information
	client = netapp_v1.NetAppClient()
	volume_name = f"projects/{myproject}/locations/{myregion}/volumes/{myvolume}"

	# Initialize request argument(s)
	request = netapp_v1.GetVolumeRequest(
		name = volume_name,
	)

	# Make the request
	response = client.get_volume(request=request)

	# Get the required information from the response
	myservicelevel = response.service_level
	mytotalvolumecapacity = response.capacity_gib
	myusedvolumecapacity = response.used_gib
	mystoragepool = response.storage_pool

	print("The service level of the storage pool ", mystoragepool," is ",myservicelevel)
	print("The location is ", myregion)
	print("The capacity of the volume ", volume_name," is ",mytotalvolumecapacity," GiB.")
	print("The used capacity of the volume ", volume_name," is ",myusedvolumecapacity," GiB.")

	# Verify if the volume has been resized previously by checking the free capacity
	myfreevolumecapacity = mytotalvolumecapacity - myusedvolumecapacity
	myfreecapacitypercentage = (myfreevolumecapacity / mytotalvolumecapacity) * 100
	if myfreecapacitypercentage > free_capacity_threshold:
		print(f"The volume has {myfreecapacitypercentage:.2f}% of free capacity (more than the {free_capacity_threshold}% threshold). Aborting the resize operation.")
		return

	# Check whether the storage pool is Standard, Premium, or Extreme (1, 2 or 3)
	if myservicelevel in [1, 2, 3]:

		# Create a client to get the storage pool information
		storagepool_name = f"projects/{myproject}/locations/{myregion}/storagePools/{mystoragepool}"

		# Initialize request argument(s)
		request = netapp_v1.GetStoragePoolRequest(
			name = storagepool_name,
		)

		# Make the request
		sp_response = client.get_storage_pool(request=request)

		# Get the required information from the response
		mystoragepoolname = sp_response.name
		mytotalstoragepoolcapacity = sp_response.capacity_gib
		myusedstoragepoolcapacity = sp_response.volume_capacity_gib
		print("The capacity of the storage pool ",mystoragepoolname," is ",mytotalstoragepoolcapacity," GiB.")

		new_vol_cap, new_sp_cap = calculate_capacity(
			mytotalvolumecapacity,
			mytotalstoragepoolcapacity,
			myusedstoragepoolcapacity,
			capacity_to_increase
		)
		increase_amount = new_vol_cap - mytotalvolumecapacity
		print("The trigger wants to increase the capacity of the volume ", volume_name," by ",increase_amount," GiB.")

		if new_sp_cap != mytotalstoragepoolcapacity:
			print("The primary storage pool will be resized to ", new_sp_cap, " GiB.")

			# Initialize request argument(s)
			storage_pool = netapp_v1.StoragePool()
			storage_pool.name = mystoragepoolname
			storage_pool.capacity_gib = new_sp_cap

			update_sp_request = netapp_v1.UpdateStoragePoolRequest(
				update_mask = "capacityGib",
				storage_pool=storage_pool,
			)

			# Make the request
			client.update_storage_pool(request=update_sp_request).result()

		# Consider replication for destination storage pool capacity
		if response.has_replication:
			try:
				replications_req = netapp_v1.ListReplicationsRequest(parent=volume_name)
				replications = client.list_replications(request=replications_req)
				for replication in replications:
					# Check if this volume is the source
					if replication.role == netapp_v1.Replication.MirrorRole.SOURCE:
						dest_vol_name = replication.destination_volume
						print(f"Volume is replicated. Checking destination storage pool for volume: {dest_vol_name}")

						dest_vol_req = netapp_v1.GetVolumeRequest(name=dest_vol_name)
						dest_vol = client.get_volume(request=dest_vol_req)
						
						dest_sp_name = dest_vol.storage_pool
						dest_location = dest_vol_name.split("/")[3]
						dest_sp_full_name = f"projects/{myproject}/locations/{dest_location}/storagePools/{dest_sp_name}"

						dest_sp_req = netapp_v1.GetStoragePoolRequest(name=dest_sp_full_name)
						dest_sp = client.get_storage_pool(request=dest_sp_req)
						
						dest_sp_free = dest_sp.capacity_gib - dest_sp.volume_capacity_gib
						
						if increase_amount > dest_sp_free:
							new_dest_sp_capacity = dest_sp.capacity_gib + increase_amount
							print("The destination storage pool will be resized to ", new_dest_sp_capacity, " GiB.")

							dest_sp_obj = netapp_v1.StoragePool(name=dest_sp_full_name, capacity_gib=new_dest_sp_capacity)
							update_dest_sp_req = netapp_v1.UpdateStoragePoolRequest(
								update_mask="capacityGib", storage_pool=dest_sp_obj
							)
							client.update_storage_pool(request=update_dest_sp_req).result()
			except Exception as e:
				print(f"Error handling replications: {e}")

		print("The primary volume will be resized to ", new_vol_cap, " GiB.")

		# Initialize request argument(s)
		volume = netapp_v1.Volume()
		volume.name = volume_name
		volume.capacity_gib = new_vol_cap

		update_vol_request = netapp_v1.UpdateVolumeRequest(
			update_mask = "capacityGib",
			volume=volume,
		)

		# Make the request
		client.update_volume(request=update_vol_request).result()

	else:
		print("The autogrow function has been defined to work only with Standard, Premium and Extreme Service levels.")
