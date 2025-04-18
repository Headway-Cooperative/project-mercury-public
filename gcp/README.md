### Setup
- Ensure you have [created a cloud billing account](https://cloud.google.com/billing/docs/how-to/create-billing-account). Take note of the project ID
- Set up [detailed usage cost data export](http://cloud.google.com/billing/docs/how-to/export-data-bigquery). Take note of the dataset name and the generated export table name.

### Deployment
Run the following commands to deploy:
```
terraform init
terraform apply
```
Terraform will prompt for input. Use the values you noted above:
```
  var.datasetName
    Enter a value: mercury_billing_data

  var.projectId
    Enter a value: crested-trainer-123456-x1
```
