# Set up cost reports

This guide provides a comprehensive overview of how to generate and view
resource-level cost reports (v0.1) for Backup and DR Service. This report lets
you gain granular insight into Backup and DR costs, helping you to optimize
spending and allocate costs to specific teams or projects.

## Understanding the cost report

The Backup and DR Service cost report offers a detailed breakdown of your Backup
and DR expenses. This report can be used by both billing administrators and
project-level backup administrators to:

*   **Optimize spending:** Identify resources with high backup costs and make
    informed decisions to optimize your backup strategy
*   **Improve visibility:** Gain a clear understanding of your spending patterns
    for backup and DR services

Important: These cost figures are derived from the billing export, which serves
as the definitive source of truth. As a result, you may see slight variances
when comparing this data to the billing dashboard on the Google Cloud console.
This report is intended for indicative purposes only and is provided without
legal or financial liability. Once the report is set up, we kindly ask that you
manage and monitor user permissions to ensure the appropriate level of access.

Details on each of the columns for Cost Report can be found in
[Resource Level Backup & DR Cost Details](#cost-details).

## Which option should you choose?

The best method for generating this cost report depends on your organization's
structure and security requirements. Depending on how you want to view the cost
report, there are two main options:

| Option           | Scenario          | Advantages        | Disadvantages     |
| :--------------- | :---------------- | :---------------- | :---------------- |
| **Option 1:      | Best for          | Centralized       | Requires backup   |
: Centralized View : scenarios where   : billing data      : administrators to :
: to a Dedicated   : all backup        : export simplifies : be given access   :
: Project**        : administrators    : management for    : to a dedicated    :
:                  : need to access    : the billing       : project, allowing :
:                  : the cost data in  : administrator.    : them access to    :
:                  : a centralized     : All backup        : view Billing data :
:                  : view and filter   : administrators    : for the Billing   :
:                  : for their own     : can view the same : Account           :
:                  : projects          : up-to-date data   :                   :
| **Option 2:      | The most secure   | Ensures strict    | Additional steps  |
: Isolated Data    : option for        : data isolation    : to be performed   :
: Sets in Each     : organizations     : and security.     : by billing and    :
: Project**        : with strict data  : Backup            : backup            :
:                  : separation        : administrators    : administrators    :
:                  : requirements,     : cannot see other  :                   :
:                  : where each backup : projects' cost    :                   :
:                  : administrator     : data, unless      :                   :
:                  : must **only** see : explicitly given  :                   :
:                  : cost data for     : access to         :                   :
:                  : their specific    :                   :                   :
:                  : project           :                   :                   :

## Detailed steps for each option

The following sections provide detailed, step-by-step instructions for each
reporting option, including how to export your billing data, configure
permissions, and view the data in BigQuery and Looker Studio:

*   [Option 1: Centralized View to a Dedicated Project](#option-1)
*   [Option 2: Isolated Data Sets in Each Project](#option-2)

## Option 1: Centralized View to a Dedicated Project {#option-1}

Follow these steps if you want to **consolidate cost reports** from multiple
Backup and DR Service deployments into a single Google Cloud project. One report
dataset and transfer job will be created in your specified target project.

### Steps for billing administrator

1.  **Export Billing Data:** In the Google Cloud console, navigate to
    **Billing** > **Billing export**. In **Detailed usage cost,** click **Edit
    Settings**. Choose a **dedicated project** as the destination. Add the name
    of the dataset for the Billing export BackupDr_Billing_Data. If the Billing
    data is already exported with a different dataset name, use that name in the
    `config.json` in Step 4.

    (If doing for the first time, the Billing data export might take 4-5 days)

2.  **Open Cloud Shell**: In the Google Cloud console, navigate to the project
    that contains your BigQuery Billing Export dataset, then click the
    **'Activate Cloud Shell'** button in the top-right corner of the console.

3.  **Setup Scripts**: Perform the following steps in Cloud Shell:

    1.  **Clone script repository from GitHub**:

        ```sh
        git clone https://github.com/GoogleCloudPlatform/storage-samples.git
        cd storage-samples/"Backup and DR"/cost-report
        ```

    2.  **Create `config.json` file**: This file provides the setup scripts with
        essential information. Create a file named `config.json` in the same
        directory, replacing the placeholder values with your specific details:

        *   `central_report_project_id`: The Project ID where the consolidated
            cost reports should be generated.
        *   `dataset`: The BigQuery dataset name containing your billing export
            data (e.g., `BackupDr_Billing_Data` from Step 1).
        *   `account_id`: Your Billing Account ID (`111111-111111-111111`).
        *   `vault_projects`: A list of project IDs where the backup vault has
            been created by the customers.
        *   `logs_dataset`: The BigQuery dataset name in your Vault projects
            containing Backup and DR Service logs.

        **Example `config.json` for Option 1**:

        ```json
        {
          "central_report_project_id": "my-central-reporting-project",
          "dataset": "BackupDr_Billing_Data",
          "account_id": "111111-111111-111111",
          "vault_projects": [ "bdr-project-a", "bdr-project-b" ],
          "logs_dataset": "bdr_reports"
        }
        ```

    3.  **Make scripts executable**:

        ```sh
        chmod +x setupscript.sh viewcreationscript.sh
        ```

    4.  **Run Setup Script**: This script creates the necessary service account,
        dataset, and BigQuery Data Transfer Service job. Run this after the
        Billing Export is complete.

        ```sh
        ./setupscript.sh
        ```

    5.  **Create Reporting View**: This script creates a summary view in
        BigQuery over the daily report tables, which simplifies connecting to
        reporting tools like Looker Studio.

        Note: Wait **24 hours** after running the setup script before running
        this script, to allow for the first scheduled data transfer to complete.

        ```sh
        ./viewcreationscript.sh
        ```

4.  **Grant Access:** After the cost tables are created in the dedicated
    project, grant access to the respective backup administrators (If they
    already don't have the access). The backup administrator should be given
    `roles/bigquery.dataViewer` and permissions on the created cost table
    BackupDr_Billing_Report

### Steps for backup administrator

1.  **View Data in BigQuery:** Navigate to the BigQuery console in the Target
    Project, where the cost table view BackupDr_Billing_Report is created. The
    billing administrator would have given you access to the dataset. Run a
    query that filters for your specific project's costs

2.  **View Data in Looker Studio:**

    *   **Start Report:** Navigate to Looker Studio and create a new report to
        begin the connection process
    *   **Select Data:** Choose the Google BigQuery connector, specifying the
        Google Cloud Project, Dataset, and Table or View
    *   **Confirm Fields:** Review the resulting data fields, rename the source,
        and click Create report
    *   **Visualize Data:** Add charts to the canvas and drag Dimensions and
        Metrics onto them to build your dashboard

## Option 2: Isolated Data Sets in Each Project {#option-2}

This option is the most secure, ensuring each backup administrator can only view
cost data for their specific project

### Steps for billing administrator

1.  **Export Billing Data:** In the Google Cloud console, navigate to
    **Billing** > **Billing export**. In **Detailed usage cost,** click **Edit
    Settings**. Choose a **dedicated project** as the destination. Add the name
    of the dataset for the Billing export BackupDr_Billing_Data. If the Billing
    data is already exported with a different dataset name, use that name in the
    `config.json` in Step 4. (If doing for the first time, the Billing data
    export might take 4-5 days)
2.  **Open Cloud Shell**: In the Google Cloud console, navigate to the project
    that contains your BigQuery Billing Export dataset, then click the
    **'Activate Cloud Shell'** button in the top-right corner of the console.
3.  **Setup Scripts**: Perform the following steps in Cloud Shell:

    1.  **Clone script repository from GitHub**:

        ```sh
        git clone https://github.com/GoogleCloudPlatform/storage-samples.git
        cd storage-samples/"Backup and DR"/cost-report
        ```

    2.  **Create `config.json` file**: This file provides the setup scripts with
        essential information. Create a file named `config.json` in the same
        directory, replacing the placeholder values with your specific details:

        *   `dataset`: The BigQuery dataset name containing your billing export
            data (e.g., `BackupDr_Billing_Data` from Step 1).
        *   `account_id`: Your Billing Account ID (`111111-111111-111111`).
        *   `vault_projects`: A list of project IDs where the backup vault has
            been created by the customers.
        *   `logs_dataset`: The BigQuery dataset name in your Vault projects
            containing Backup and DR Service logs.

        **Example `config.json` for Option 2**:

        ```json
        {
          "dataset": "BackupDr_Billing_Data",
          "account_id": "111111-111111-111111",
          "vault_projects": [ "bdr-project-a", "bdr-project-b" ],
          "logs_dataset": "bdr_reports"
        }
        ```

    3.  **Make scripts executable**:

        ```sh
        chmod +x setupscript.sh viewcreationscript.sh
        ```

    4.  **Run Setup Script**: This script creates the necessary service account,
        dataset, and BigQuery Data Transfer Service job. Run this after the
        Billing Export is complete.

        ```sh
        ./setupscript.sh
        ```

    5.  **Create Reporting View**: This script creates a summary view in
        BigQuery over the daily report tables, which simplifies connecting to
        reporting tools like Looker Studio.

        Note: Wait **24 hours** after running the setup script before running
        this script, to allow for the first scheduled data transfer to complete.

        ```sh
        ./viewcreationscript.sh
        ```

4.  **Grant Access:** After the cost tables are created in the dedicated
    project, grant access to the respective backup administrators (If they
    already don't have the access). The backup administrator should be given
    `roles/bigquery.dataViewer` and permissions on the created cost table
    `BackupDr_Billing_Report`.

### Steps for backup administrator

1.  **View Data in BigQuery:** Navigate to the BigQuery console in the selected
    Vault Project, where the cost table view BackupDr_Billing_Report is created.
    Run a query to view your project's Backup & DR costs

2.  **View Data in Looker Studio:**

    *   **Start Report:** Navigate to Looker Studio and create a new report to
        begin the connection process
    *   **Select Data:** Choose the Google BigQuery connector, specifying the
        Google Cloud Project, Dataset, and Table or View
    *   **Confirm Fields:** Review the resulting data fields, rename the source,
        and click Create report
    *   **Visualize Data:** Add charts to the canvas and drag Dimensions and
        Metrics onto them to build your dashboard

## Resource level Backup and DR Service cost details {#cost-details}

The cost report includes the following columns:

| Column                   | Description                                       |
| :----------------------- | :------------------------------------------------ |
| `report_date`            | Date for the Billing usage of the resource        |
| `resource_name`          | Name of the resource as configured on Google      |
:                          : Cloud console                                     :
| `resource_type`          | Type of the resource                              |
| `backup_vault_type`      | Type of Backup Vault protecting the resource      |
| `resource`               | Short name for the resource                       |
| `billing_location`       | Location in which the resource is billed          |
| `usage_in_pricing_units` | Usage corresponding to the backup of the resource |
| `usage_pricing_unit`     | Unit for determining the usage                    |
| `cost`                   | Resource cost inclusive of any negotiated         |
:                          : discounts                                         :
| `currency`               | Currency Unit                                     |
| `credits`                | Sum of all credits of all types applicable for    |
:                          : the resource.                                     :
| `net_cost`               | The final cost after all credits are applied      |
:                          : (cost + credits).                                 :
| `sku_description`        | sku.description from billing data                 |
| `sku_id`                 | sku.id from billing data                          |
| `backup_vault_name`      | Name of backup vault protecting the resource      |
| `resource_location`      | Regional location of the resource                 |
| `backup_plan_name`       | Name of the Backup plan associated to the         |
:                          : resource                                          :
| `backup_vault_location`  | Location of the Backup vault associated to the    |
:                          : resource                                          :
| `source_project`         | Workload project associated to the resource       |
