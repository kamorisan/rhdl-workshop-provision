# Etherpad - Shared Collaborative Notepad

This directory contains the GitOps configuration for deploying Etherpad to the Developer Lightspeed Workshop environment.

## Overview

Etherpad is a real-time collaborative editor that allows multiple users to simultaneously edit documents. This deployment includes:

- **Etherpad Application**: Web-based collaborative text editor
- **PostgreSQL Database**: Persistent storage for pads and user data
- **OpenShift Route**: HTTPS access to the Etherpad instance

## Architecture

```
┌─────────────────────────────────────────┐
│ ArgoCD Application                      │
│ - Auto-sync enabled                     │
│ - Namespace: etherpad                   │
└─────────────────────────────────────────┘
                  │
                  ▼
┌─────────────────────────────────────────┐
│ Etherpad Deployment                     │
│ - Image: quay.io/wkulhanek/etherpad     │
│ - Port: 9001                            │
│ - Replicas: 1                           │
└─────────────────────────────────────────┘
                  │
                  ▼
┌─────────────────────────────────────────┐
│ PostgreSQL Database                     │
│ - Version: 13                           │
│ - Storage: 10Gi PVC                     │
│ - Database: etherpad                    │
└─────────────────────────────────────────┘
```

## Files

```
etherpad/
├── application.yaml          # ArgoCD Application definition
├── chart/
│   ├── Chart.yaml           # Helm chart metadata
│   ├── values.yaml          # Default values
│   └── templates/
│       ├── configmap.yaml   # Etherpad settings.json
│       ├── deployment.yaml  # Etherpad Deployment
│       ├── postgresql.yaml  # PostgreSQL resources
│       ├── route.yaml       # OpenShift Route
│       └── service.yaml     # Etherpad Service
└── README.md                # This file
```

## Configuration

Configuration is managed in `gitops/config/etherpad-values.yaml`:

```yaml
etherpad:
  adminPassword: "workshop2024!"  # Change in production!
  
postgresql:
  password: "etherpad123!"        # Change in production!
```

### Important Settings

| Setting | Description | Default |
|---------|-------------|---------|
| `etherpad.adminPassword` | Admin user password | `workshop2024!` |
| `postgresql.database` | Database name | `etherpad` |
| `postgresql.username` | Database user | `ether` |
| `postgresql.password` | Database password | `etherpad123!` |
| `postgresql.volumeCapacity` | PVC size | `10Gi` |

## Deployment

### Via GitOps (Recommended)

The Etherpad application is automatically deployed via ArgoCD when the platform-instances are applied:

```bash
# Sync all platform instances
oc apply -k gitops/platform-instances/
```

### Manual Deployment (Testing)

For testing the Helm chart locally:

```bash
# Render templates
helm template etherpad \
  gitops/platform-instances/etherpad/chart \
  -f gitops/config/etherpad-values.yaml

# Apply directly (not recommended for production)
helm template etherpad \
  gitops/platform-instances/etherpad/chart \
  -f gitops/config/etherpad-values.yaml | \
  oc apply -f -
```

## Accessing Etherpad

After deployment, access Etherpad via the OpenShift Route:

```bash
# Get the Etherpad URL
ETHERPAD_URL=$(oc get route etherpad -n etherpad -o jsonpath='{.spec.host}')
echo "Etherpad URL: https://${ETHERPAD_URL}"
```

### Admin Access

- **URL**: `https://<route>/admin`
- **Username**: `admin`
- **Password**: Value of `etherpad.adminPassword` in values.yaml

## Resource Requirements

### Etherpad

- **Requests**: 200m CPU, 512Mi Memory
- **Limits**: 1000m CPU, 1Gi Memory

### PostgreSQL

- **Requests**: 100m CPU, 256Mi Memory
- **Limits**: 500m CPU, 512Mi Memory
- **Storage**: 10Gi PVC

## Sync Waves

The deployment uses ArgoCD sync waves to ensure proper ordering:

1. Wave 30: Secret, ConfigMap, Service, PVC, Route
2. Wave 35: PostgreSQL Deployment
3. Wave 40: Etherpad Deployment

This ensures PostgreSQL is ready before Etherpad starts.

## Troubleshooting

### Etherpad Pod Not Starting

Check PostgreSQL is ready:

```bash
oc get pods -n etherpad
oc logs -n etherpad deployment/postgresql
```

### Database Connection Issues

Verify database credentials:

```bash
oc get secret postgresql -n etherpad -o yaml
```

### Check Etherpad Logs

```bash
oc logs -n etherpad deployment/etherpad
```

### Reset Database

**WARNING**: This will delete all pads!

```bash
# Delete PostgreSQL PVC and recreate
oc delete pvc postgresql -n etherpad
oc delete pod -n etherpad -l app=etherpad_db
```

## Customization

### Change Admin Password

Edit `gitops/config/etherpad-values.yaml`:

```yaml
etherpad:
  adminPassword: "your-secure-password"
```

Commit and push - ArgoCD will auto-sync.

### Change Default Pad Text

Edit `chart/templates/configmap.yaml` and modify the `defaultPadText` field.

### Adjust Resource Limits

Edit `gitops/config/etherpad-values.yaml`:

```yaml
etherpad:
  resources:
    limits:
      cpu: 2000m
      memory: 2Gi
```

## Backup and Restore

### Backup Database

```bash
# Get PostgreSQL pod
POD=$(oc get pods -n etherpad -l app=etherpad_db -o name | head -1)

# Dump database
oc exec -n etherpad "$POD" -- bash -c \
  "pg_dump -U ether etherpad" > etherpad-backup.sql
```

### Restore Database

```bash
# Copy backup to pod
oc cp etherpad-backup.sql etherpad/$POD:/tmp/

# Restore
oc exec -n etherpad "$POD" -- bash -c \
  "psql -U ether etherpad < /tmp/etherpad-backup.sql"
```

## Security Considerations

1. **Change default passwords** in production
2. **Enable authentication** if exposing publicly
3. **Regular backups** of PostgreSQL database
4. **Monitor resource usage** and adjust limits as needed
5. **Keep Etherpad image updated** for security patches

## References

- [Etherpad Official Documentation](https://etherpad.org/)
- [Etherpad GitHub](https://github.com/ether/etherpad-lite)
- [Container Image Source](https://quay.io/repository/wkulhanek/etherpad)
