# k8s-infra Documentation

Comprehensive documentation for the Kubernetes infrastructure and CI/CD pipelines.

## Table of Contents

### 📖 Core Documentation

1. **[Architecture Overview](architecture.md)**
   - System architecture and component overview
   - Network topology
   - Data flow diagrams
   - Technology stack

2. **[GitHub Actions CI/CD](github-actions.md)**
   - Automated deployment pipelines
   - RBAC configuration
   - Security setup
   - Workflow reference

3. **[ArgoCD Setup](argocd-setup.md)**
   - Installation and configuration
   - Application deployment
   - Access and monitoring

4. **[ArgoCD GitOps Integration](argocd-gitops.md)**
   - GitOps workflow with GitHub Actions
   - Automated deployments
   - Multi-environment strategies

5. **[Samba File Share](samba-share.md)**
   - LAN file sharing setup
   - Platform-specific connection guides
   - Security and performance

### 🔧 Reference Guides

6. **[Quick Reference](quick-reference.md)**
   - Common commands
   - Connection settings
   - Useful snippets

7. **[Troubleshooting Guide](troubleshooting.md)**
   - Common issues and solutions
   - Diagnostic commands
   - Recovery procedures

## Quick Links

### Getting Started

**New installation:**
```bash
# 1. Setup GitHub Actions for infrastructure deployment
./scripts/setup-github-actions.sh

# 2. Install ArgoCD for GitOps
./scripts/argocd/install-argocd.sh

# 3. Setup Samba for file sharing
./scripts/setup-samba.sh
```

**Key documentation:**
- First time? Start with [Architecture Overview](architecture.md)
- Setting up CI/CD? See [GitHub Actions](github-actions.md)
- Deploying apps? Check [ArgoCD GitOps](argocd-gitops.md)
- Need quick answers? Try [Quick Reference](quick-reference.md)

### Component Access

| Component | Access Method | Documentation |
|-----------|---------------|---------------|
| **k3s Cluster** | `kubectl` | [Quick Reference](quick-reference.md#kubernetes) |
| **ArgoCD UI** | Port-forward or Ingress | [ArgoCD Setup](argocd-setup.md#accessing-argocd) |
| **Samba Share** | `\\<node-ip>\share` | [Samba Share](samba-share.md#connecting) |
| **GitHub Actions** | GitHub repo → Actions tab | [GitHub Actions](github-actions.md) |

### Common Tasks

| Task | Command | Documentation |
|------|---------|---------------|
| Deploy infrastructure | GitHub Actions or `kubectl apply -k infrastructure/` | [GitHub Actions](github-actions.md) |
| Deploy application | Push to app repo (GitOps) | [ArgoCD GitOps](argocd-gitops.md) |
| Check cluster status | `kubectl get nodes,pods -A` | [Quick Reference](quick-reference.md) |
| View ArgoCD apps | `kubectl get applications -n argocd` | [ArgoCD Setup](argocd-setup.md) |
| Access Samba | `\\<node-ip>\share` | [Samba Share](samba-share.md) |
| Troubleshoot issues | See diagnostic commands | [Troubleshooting](troubleshooting.md) |

## Documentation Organization

### By Component

- **Infrastructure as Code**: All manifests in `apps/` and `infrastructure/`
- **Automation**: Scripts in `scripts/`
- **CI/CD**: Workflows in `.github/workflows/`
- **GitOps**: ArgoCD applications in `argocd/applications/`
- **Documentation**: This `docs/` directory

### By Use Case

**I want to...**
- Deploy infrastructure changes → [GitHub Actions](github-actions.md)
- Deploy application updates → [ArgoCD GitOps](argocd-gitops.md)
- Share files on LAN → [Samba Share](samba-share.md)
- Understand the system → [Architecture](architecture.md)
- Fix an issue → [Troubleshooting](troubleshooting.md)
- Find a command → [Quick Reference](quick-reference.md)

## Contributing to Documentation

When adding new components or features:

1. Update relevant documentation files
2. Add architecture diagrams if applicable
3. Include example commands
4. Update this README with new links
5. Add troubleshooting entries if needed

## Documentation Standards

- **ASCII diagrams** for architecture and flows
- **Code blocks** with syntax highlighting
- **Tables** for reference information
- **Examples** with real commands
- **Links** between related documentation

## Support

For issues not covered in documentation:

1. Check [Troubleshooting Guide](troubleshooting.md)
2. Review component logs (commands in [Quick Reference](quick-reference.md))
3. Consult upstream documentation:
   - [Kubernetes](https://kubernetes.io/docs/)
   - [k3s](https://docs.k3s.io/)
   - [ArgoCD](https://argo-cd.readthedocs.io/)
   - [GitHub Actions](https://docs.github.com/en/actions)

## Version Information

- **k3s**: v1.28+
- **ArgoCD**: Latest stable
- **GitHub Actions**: Runner ubuntu-latest
- **Samba**: dperson/samba:latest

Last updated: 2025-11-19
