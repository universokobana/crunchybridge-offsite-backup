# CBOB Architecture Overview

This document describes the architecture and design of CBOB v2.

## Table of Contents
- [System Overview](#system-overview)
- [Component Architecture](#component-architecture)
- [Data Flow](#data-flow)
- [Security Architecture](#security-architecture)
- [Deployment Architecture](#deployment-architecture)
- [Technology Stack](#technology-stack)

## System Overview

CBOB (Crunchy Bridge Off-site Backup) is a comprehensive backup management system designed to:

1. **Sync** backups from Crunchy Bridge (AWS S3) to local or alternative storage
2. **Replicate** backups across multiple regions and cloud providers
3. **Validate** backup integrity using pgBackRest
4. **Monitor** backup health and performance
5. **Automate** backup operations with scheduling and notifications

### High-Level Architecture

```
┌─────────────────┐     ┌──────────────────┐     ┌─────────────────┐
│ Crunchy Bridge  │     │      CBOB        │     │   Replicas      │
│                 │     │                  │     │                 │
│ ┌─────────────┐ │     │ ┌──────────────┐ │     │ ┌─────────────┐ │
│ │ PostgreSQL  │ │     │ │     CLI      │ │     │ │  AWS S3 EU  │ │
│ └─────────────┘ │     │ └──────────────┘ │     │ └─────────────┘ │
│        │        │     │        │        │     │                 │
│ ┌─────────────┐ │     │ ┌──────────────┐ │     │ ┌─────────────┐ │
│ │ pgBackRest  │ │────▶│ │ Sync Engine  │ │────▶│ │ Azure Blob  │ │
│ └─────────────┘ │     │ └──────────────┘ │     │ └─────────────┘ │
│        │        │     │        │        │     │                 │
│ ┌─────────────┐ │     │ ┌──────────────┐ │     │ ┌─────────────┐ │
│ │   AWS S3    │ │     │ │ Replication  │ │     │ │ GCP Storage │ │
│ └─────────────┘ │     │ └──────────────┘ │     │ └─────────────┘ │
└─────────────────┘     └──────────────────┘     └─────────────────┘
```

## Component Architecture

### 1. CLI Layer (`bin/`)

The command-line interface provides user interaction:

```
bin/
├── cbob                  # Main CLI entry point
├── cbob-sync            # Backup synchronization
├── cbob-restore-check   # Integrity validation
├── cbob-info            # Information display
├── cbob-expire          # Backup expiration
├── cbob-postgres        # PostgreSQL management
├── cbob-replicate       # Multi-region replication
└── cbob-config          # Configuration management
```

**Key Features:**
- Modular subcommand architecture
- Global options inheritance
- Consistent error handling
- Progress indicators

### 2. Library Layer (`lib/`)

Core functionality libraries:

```
lib/
├── cbob_common.sh       # Common functions (logging, config, etc.)
├── cbob_security.sh     # Security functions (validation, encryption)
├── cbob_metrics.sh      # Metrics collection and reporting
└── cbob_replication.sh  # Multi-region replication engine
```

**Key Components:**

#### cbob_common.sh
- Logging functions with structured output
- Configuration loading and validation
- Lock file management
- Dependency checking
- Retry mechanisms

#### cbob_security.sh
- Input validation and sanitization
- Credential management
- Audit logging
- Permission checking

#### cbob_metrics.sh
- Metrics collection
- Performance tracking
- Storage analytics
- Report generation

#### cbob_replication.sh
- Provider abstraction layer
- Multi-cloud support
- State management
- Health monitoring

### 3. Storage Layer

Multiple storage providers supported:

```
Storage Providers
├── AWS S3 (Primary)
├── Azure Blob Storage
├── Google Cloud Storage
├── DigitalOcean Spaces
└── MinIO (Self-hosted)
```

**Storage Architecture:**
- Provider abstraction for portability
- Parallel transfer support
- Bandwidth management
- Checksum verification

## Data Flow

### 1. Backup Sync Flow

```
1. Crunchy Bridge API
   ↓
2. Get backup credentials
   ↓
3. AWS S3 Sync
   ↓
4. Local Storage
   ↓
5. Metrics Recording
   ↓
6. Notifications
```

### 2. Replication Flow

```
1. Local Storage (Primary)
   ↓
2. Read Configuration
   ↓
3. Provider Selection
   ↓
4. Parallel Replication ──┬──▶ AWS S3 (Region 2)
                         ├──▶ Azure Blob
                         ├──▶ GCP Storage
                         └──▶ DO Spaces
   ↓
5. Verification
   ↓
6. State Update
```

### 3. Restore Check Flow

```
1. Select Stanza
   ↓
2. pgbackrest_auto
   ↓
3. Restore to temp location
   ↓
4. Validate database
   ↓
5. Generate report
   ↓
6. Cleanup
```

## Security Architecture

### Authentication & Authorization

```
┌─────────────────┐
│ Authentication  │
├─────────────────┤
│ • API Keys      │
│ • IAM Roles     │
│ • Certificates  │
└─────────────────┘
        │
        ▼
┌─────────────────┐
│ Authorization   │
├─────────────────┤
│ • Role-based    │
│ • Path-based    │
│ • Operation ACL │
└─────────────────┘
```

### Data Security

1. **In Transit**
   - TLS 1.2+ for all connections
   - Certificate validation
   - Encrypted tunnels for replication

2. **At Rest**
   - Provider-native encryption (SSE-S3, etc.)
   - Optional client-side encryption
   - Secure credential storage

3. **Access Control**
   - Minimal IAM permissions
   - Separate credentials per operation
   - Audit logging for all operations

## Deployment Architecture

### 1. Standalone Deployment

```
┌─────────────────┐
│   Single Host   │
├─────────────────┤
│ • CBOB CLI      │
│ • Cron Jobs     │
│ • Local Storage │
│ • pgBackRest    │
└─────────────────┘
```

### 2. Docker Deployment

```
┌─────────────────┐
│ Docker Compose  │
├─────────────────┤
│ ┌─────────────┐ │
│ │ CBOB Cron   │ │
│ └─────────────┘ │
│ ┌─────────────┐ │
│ │  Volumes    │ │
│ │ (backups)   │ │
│ └─────────────┘ │
└─────────────────┘
```

### 3. Kubernetes Deployment (Future)

```
┌─────────────────────────┐
│    Kubernetes Cluster   │
├─────────────────────────┤
│ ┌─────────┐ ┌─────────┐│
│ │ API Pod │ │CronJob  ││
│ └─────────┘ └─────────┘│
│ ┌─────────┐ ┌─────────┐│
│ │ConfigMap│ │ Secret  ││
│ └─────────┘ └─────────┘│
│ ┌───────────────────┐  │
│ │   PVC Storage     │  │
│ └───────────────────┘  │
└─────────────────────────┘
```

## Technology Stack

### Core Technologies

| Component | Technology | Purpose |
|-----------|------------|---------|
| Shell Scripts | Bash 4.4+ | CLI and automation |
| Backup Tool | pgBackRest | PostgreSQL backups |
| Cloud CLI | AWS CLI v2 | S3 operations |
| Configuration | YAML | Replication config |
| JSON Processing | jq | Metrics and logging |

### Dependencies

**System Packages:**
- postgresql-client-18
- pgbackrest
- aws-cli
- azure-cli (optional, for Azure replication)
- gsutil (optional, for GCP replication)
- jq
- curl

### Integration Points

1. **Crunchy Bridge API**
   - Authentication
   - Cluster information
   - Backup credentials

2. **Cloud Storage APIs**
   - AWS S3 API
   - Azure Blob REST API
   - Google Cloud Storage API
   - DigitalOcean Spaces API

3. **Monitoring Systems**
   - Heartbeat endpoints (Cronitor, Healthchecks.io, etc.)
   - Slack notifications
   - Email (SMTP)
   - Structured JSON logging

## Design Principles

### 1. Modularity
- Separate concerns into distinct modules
- Plugin architecture for storage providers
- Composable CLI commands

### 2. Reliability
- Retry mechanisms with backoff
- State management for recovery
- Comprehensive error handling

### 3. Performance
- Parallel operations where possible
- Bandwidth management
- Efficient resource usage

### 4. Security
- Defense in depth
- Principle of least privilege
- Audit trail for compliance

### 5. Observability
- Structured logging
- Metrics collection
- Health checks
- Progress indicators

## Future Architecture Considerations

### Planned Enhancements

1. **Web UI**
   - React-based dashboard
   - Real-time monitoring
   - Visual backup management

2. **Kubernetes Operator**
   - CRD for backup policies
   - Automated scheduling
   - Multi-tenant support

3. **Plugin System**
   - Custom storage providers
   - Notification integrations
   - Policy engines

4. **Distributed Architecture**
   - Multi-node support
   - Leader election
   - Work distribution