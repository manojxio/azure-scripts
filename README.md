# Azure Scripts

A collection of reusable Azure automation scripts for common administration and maintenance tasks.

## Repository Structure

```text
azure-scripts/
├── README.md
└── acr/
    └── delete-images.sh
```

## Scripts

### ACR

#### `delete-images.sh`

Safely deletes old image manifests from an Azure Container Registry (ACR) repository.

**Features**

* Prompts for:

  * Azure Container Registry name
  * Repository name
  * Retention period (default: 20 days)
* Shows:

  * Total manifests
  * Protected manifests (`main` and `test`)
  * Manifests that will be deleted
* Lists all manifests before deletion.
* Requires explicit confirmation before deleting.
* Never deletes manifests tagged `main` or `test`.

**Prerequisites**

* Azure CLI
* `jq`
* Logged in to Azure

```bash
az login
```

**Usage**

```bash
chmod +x acr/delete-images.sh

./acr/delete-images.sh
```

**Example**

```text
Enter Azure Container Registry name: myregistry
Enter repository name: backend
Delete images older than how many days? [20]:
```
