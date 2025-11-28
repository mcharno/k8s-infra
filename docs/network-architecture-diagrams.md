# Network Architecture Diagrams

This document contains multiple Mermaid diagrams showing the hybrid network setup from different perspectives and detail levels.

## Diagram Index

1. [High-Level Overview](#high-level-overview)
2. [External Access Flow (Detailed)](#external-access-flow-detailed)
3. [Local Access Flow (Detailed)](#local-access-flow-detailed)
4. [Certificate Management Architecture](#certificate-management-architecture)
5. [Nginx Ingress Routing](#nginx-ingress-routing)
6. [Complete System Architecture](#complete-system-architecture)
7. [Application Configuration Pattern](#application-configuration-pattern)
8. [Network Segmentation](#network-segmentation)

---

## High-Level Overview

```mermaid
graph TB
    subgraph Internet["🌐 Internet Users"]
        ExtUser[External User<br/>Anywhere]
    end
    
    subgraph Home["🏠 Home Network Users"]
        LocalUser[Local User<br/>192.168.0.0/24]
    end
    
    subgraph Cloudflare["☁️ Cloudflare"]
        CFEdge[Edge Servers<br/>DDoS Protection<br/>SSL Termination]
        CFTunnel[Cloudflare Tunnel<br/>Encrypted Connection]
    end
    
    subgraph Router["🌐 Home Router"]
        PortFwd[Port Forward<br/>443→30443]
    end
    
    subgraph Pi["🥧 Raspberry Pi"]
        subgraph System["System Services"]
            CloudflaredDaemon[cloudflared<br/>Tunnel Client]
        end
        
        subgraph K3s["Kubernetes (K3s)"]
            NginxIngress[Nginx Ingress<br/>:30280 HTTP<br/>:30443 HTTPS]
            Services[Application<br/>Services]
        end
    end
    
    ExtUser -->|HTTPS| CFEdge
    CFEdge -->|Encrypted Tunnel| CFTunnel
    CFTunnel -->|Encrypted| CloudflaredDaemon
    CloudflaredDaemon -->|HTTP| NginxIngress
    
    LocalUser -->|HTTPS:443| PortFwd
    PortFwd -->|HTTPS:30443| NginxIngress
    
    NginxIngress -->|HTTP| Services
    
    style Internet fill:#e1f5ff
    style Home fill:#fff4e1
    style Cloudflare fill:#f9a825
    style Pi fill:#c8e6c9
    style K3s fill:#b2dfdb
```

---

## External Access Flow (Detailed)

```mermaid
sequenceDiagram
    participant User as 🧑 User<br/>(Anywhere)
    participant CFEdge as ☁️ Cloudflare Edge
    participant CFTunnel as 🔒 Tunnel
    participant Daemon as cloudflared<br/>(Pi)
    participant Nginx as Nginx Ingress<br/>:30280
    participant Service as K8s Service
    participant Pod as Application Pod
    
    Note over User,Pod: External Access Flow
    
    User->>CFEdge: HTTPS Request<br/>nextcloud.charn.io
    Note over CFEdge: DDoS Protection<br/>Bot Detection<br/>SSL Termination
    
    CFEdge->>CFEdge: Validate Request
    CFEdge->>CFTunnel: Forward via Tunnel
    Note over CFTunnel: Encrypted Connection<br/>Outbound Only
    
    CFTunnel->>Daemon: HTTP Request<br/>Host: nextcloud.charn.io
    Note over Daemon: systemd service<br/>localhost:30280
    
    Daemon->>Nginx: HTTP Request<br/>Port 30280
    Note over Nginx: Check Host header<br/>Find matching Ingress
    
    Nginx->>Nginx: Route to nextcloud
    Note over Nginx: Add X-Forwarded-*<br/>headers
    
    Nginx->>Service: HTTP to nextcloud:80
    Service->>Pod: Forward to Pod IP:80
    
    Pod->>Pod: Process Request<br/>Read X-Forwarded-Host
    Pod-->>Service: HTTP Response
    Service-->>Nginx: Forward Response
    
    Nginx->>Nginx: Add Headers
    Nginx-->>Daemon: HTTP Response
    Daemon-->>CFTunnel: Response
    CFTunnel-->>CFEdge: Encrypted Response
    
    CFEdge->>CFEdge: Add HTTPS headers
    CFEdge-->>User: HTTPS Response
    
    Note over User: Response includes<br/>https://nextcloud.charn.io URLs
```

---

## Local Access Flow (Detailed)

```mermaid
sequenceDiagram
    participant User as 🧑 User<br/>(Home Network)
    participant Router as 🌐 Router
    participant Nginx as Nginx Ingress<br/>:30443
    participant CertSecret as TLS Secret
    participant Service as K8s Service
    participant Pod as Application Pod
    
    Note over User,Pod: Local Access Flow
    
    User->>Router: HTTPS Request<br/>nextcloud.local.charn.io:443
    Note over Router: Port Forward<br/>443 → 192.168.0.23:30443
    
    Router->>Nginx: HTTPS Request :30443
    Note over Nginx: TLS Handshake
    
    Nginx->>CertSecret: Get Certificate<br/>nextcloud-local-tls
    CertSecret-->>Nginx: Certificate + Key
    
    Nginx->>Nginx: Complete TLS Handshake
    Note over Nginx: SSL Termination<br/>Decrypt HTTPS
    
    Nginx->>Nginx: Check Host header<br/>Find Ingress
    Note over Nginx: Match:<br/>nextcloud-local ingress
    
    Nginx->>Nginx: Add Headers<br/>X-Forwarded-*
    
    Nginx->>Service: HTTP to nextcloud:80
    Service->>Pod: Forward to Pod
    
    Pod->>Pod: Process Request<br/>Read X-Forwarded-Host
    Pod-->>Service: HTTP Response
    Service-->>Nginx: Response
    
    Nginx->>Nginx: Encrypt with TLS
    Nginx-->>Router: HTTPS Response
    Router-->>User: HTTPS Response
    
    Note over User: Response includes<br/>https://nextcloud.local.charn.io URLs
```

---

## Certificate Management Architecture

```mermaid
graph TB
    subgraph LetsEncrypt["🔐 Let's Encrypt CA"]
        ACME[ACME Server]
    end
    
    subgraph CertManager["📜 cert-manager (K8s)"]
        CMController[cert-manager<br/>Controller]
        
        subgraph Issuers
            DNSIssuer[ClusterIssuer<br/>letsencrypt-cloudflare-prod<br/>DNS-01]
            HTTPIssuer[ClusterIssuer<br/>letsencrypt-http-prod<br/>HTTP-01]
        end
        
        subgraph Certificates
            WildcardCert[Certificate<br/>*.charn.io<br/>*.charno.net]
            LocalCerts[Certificates<br/>*.local.charn.io<br/>Individual]
        end
        
        subgraph Secrets
            WildcardSecret[Secret<br/>charn-io-wildcard-tls]
            LocalSecrets[Secrets<br/>*-local-tls]
        end
    end
    
    subgraph Cloudflare["☁️ Cloudflare"]
        CFAPI[DNS API]
        CFToken[API Token<br/>Secret]
    end
    
    subgraph Ingresses["🔀 Ingress Resources"]
        ExtIngress[External Ingresses<br/>*.charn.io]
        LocIngress[Local Ingresses<br/>*.local.charn.io]
    end
    
    CMController -->|Watches| Ingresses
    Ingresses -->|References| DNSIssuer
    Ingresses -->|References| HTTPIssuer
    
    DNSIssuer -->|Uses| CFToken
    DNSIssuer -->|DNS Challenge| CFAPI
    CFAPI -->|TXT Record| ACME
    
    HTTPIssuer -->|HTTP Challenge<br/>/.well-known/| ACME
    
    ACME -->|Issue Certificate| WildcardCert
    ACME -->|Issue Certificates| LocalCerts
    
    WildcardCert -->|Stores in| WildcardSecret
    LocalCerts -->|Store in| LocalSecrets
    
    ExtIngress -->|Uses| WildcardSecret
    LocIngress -->|Use| LocalSecrets
    
    WildcardSecret -.->|Copied to| AppNamespaces[App Namespaces]
    
    style LetsEncrypt fill:#4CAF50
    style Cloudflare fill:#f9a825
    style CertManager fill:#2196F3
    style Ingresses fill:#9C27B0
```

---

## Nginx Ingress Routing

```mermaid
graph LR
    subgraph Requests["📨 Incoming Requests"]
        ExtReq[External Request<br/>:30280 HTTP<br/>Host: app.charn.io]
        LocReq[Local Request<br/>:30443 HTTPS<br/>Host: app.local.charn.io]
    end
    
    subgraph NginxIngress["🔀 Nginx Ingress Controller"]
        Listener30280[Listener :30280<br/>HTTP]
        Listener30443[Listener :30443<br/>HTTPS]
        
        SSL[SSL/TLS<br/>Termination]
        
        Router[Ingress Router<br/>Match by Host Header]
        
        subgraph ConfigMap
            NoRedirect[ssl-redirect: false<br/>No 308 loops]
            ForwardHeaders[use-forwarded-headers: true<br/>Trust X-Forwarded-*]
        end
    end
    
    subgraph IngressRules["📋 Ingress Rules"]
        ExtRule[app-external<br/>Host: app.charn.io<br/>Cert: wildcard-tls]
        LocRule[app-local<br/>Host: app.local.charn.io<br/>Cert: app-local-tls]
    end
    
    subgraph Services["⚙️ Services"]
        AppSvc[Service: app<br/>Port: 8080]
    end
    
    subgraph Pods["📦 Pods"]
        AppPod1[app-pod-1<br/>10.42.0.x:8080]
        AppPod2[app-pod-2<br/>10.42.0.y:8080]
    end
    
    ExtReq -->|HTTP| Listener30280
    LocReq -->|HTTPS| Listener30443
    
    Listener30443 -->|Decrypt| SSL
    SSL -->|HTTP| Router
    Listener30280 -->|HTTP| Router
    
    Router -->|Match Host| ExtRule
    Router -->|Match Host| LocRule
    
    ExtRule -->|Backend| AppSvc
    LocRule -->|Backend| AppSvc
    
    AppSvc -->|Load Balance| AppPod1
    AppSvc -->|Load Balance| AppPod2
    
    ConfigMap -.->|Configures| Router
    
    style Requests fill:#e1f5ff
    style NginxIngress fill:#4CAF50
    style IngressRules fill:#2196F3
    style Services fill:#FF9800
    style Pods fill:#9C27B0
```

---

## Complete System Architecture

```mermaid
graph TB
    subgraph External["🌐 External Network"]
        Users[Internet Users]
    end
    
    subgraph CloudflareNetwork["☁️ Cloudflare Network"]
        CFEdge[Edge Servers<br/>200+ Locations]
        CFTunnel[Tunnel Service]
        CFDNS[DNS Service<br/>*.charn.io<br/>*.charno.net]
    end
    
    subgraph LocalNetwork["🏠 Home Network 192.168.0.0/24"]
        LocalUsers[Local Users]
        Router[Router/Firewall<br/>Port Forwards:<br/>443→30443<br/>80→30280]
        LocalDNS[Local DNS<br/>*.local.charn.io<br/>→192.168.0.23]
    end
    
    subgraph RaspberryPi["🥧 Raspberry Pi 192.168.0.23"]
        subgraph SystemServices["System Services"]
            Cloudflared[cloudflared Daemon<br/>systemd]
            OS[Ubuntu Server<br/>ARM64]
        end
        
        subgraph K3sCluster["Kubernetes (K3s)"]
            subgraph IngressNS["ingress-nginx namespace"]
                NginxController[Nginx Ingress<br/>Controller]
                NginxConfig[ConfigMap<br/>ssl-redirect: false]
            end
            
            subgraph CertManagerNS["cert-manager namespace"]
                CertMgr[cert-manager]
                DNSIssuer[ClusterIssuer<br/>DNS-01]
                HTTPIssuer[ClusterIssuer<br/>HTTP-01]
                WildcardCerts[Wildcard Certs<br/>*.charn.io<br/>*.charno.net]
            end
            
            subgraph AppNamespaces["Application Namespaces"]
                Homer[homer]
                Nextcloud[nextcloud]
                Jellyfin[jellyfin]
                HomeAssistant[homeassistant]
                Grafana[grafana]
                Others[...]
            end
            
            subgraph DatabaseNS["database namespace"]
                PostgreSQL[PostgreSQL<br/>Shared]
                Redis[Redis<br/>Shared]
            end
        end
        
        Storage[(External Storage<br/>2.7TB SSD)]
    end
    
    Users -->|HTTPS| CFEdge
    CFEdge <-->|DNS| CFDNS
    CFEdge -->|Tunnel| CFTunnel
    CFTunnel -->|Encrypted<br/>Outbound Only| Cloudflared
    
    LocalUsers -->|DNS Query| LocalDNS
    LocalUsers -->|HTTPS:443| Router
    Router -->|HTTPS:30443| NginxController
    
    Cloudflared -->|HTTP:30280| NginxController
    
    NginxController -->|Routes by Host| AppNamespaces
    NginxConfig -.->|Configures| NginxController
    
    CertMgr -->|Manages| WildcardCerts
    DNSIssuer -->|DNS-01| CFEdge
    HTTPIssuer -->|HTTP-01<br/>:30280| NginxController
    
    WildcardCerts -.->|Copied to| AppNamespaces
    
    AppNamespaces -->|Persistent Data| Storage
    AppNamespaces -->|Database| PostgreSQL
    AppNamespaces -->|Cache| Redis
    
    OS -.->|Manages| K3sCluster
    
    style External fill:#e1f5ff
    style CloudflareNetwork fill:#f9a825
    style LocalNetwork fill:#fff4e1
    style RaspberryPi fill:#c8e6c9
    style K3sCluster fill:#b2dfdb
```

---

## Application Configuration Pattern

```mermaid
graph TB
    subgraph Request["📨 Request"]
        ReqExt[Request via<br/>app.charn.io]
        ReqLoc[Request via<br/>app.local.charn.io]
    end
    
    subgraph Nginx["🔀 Nginx Ingress"]
        AddHeaders[Add Headers:<br/>X-Forwarded-Host<br/>X-Forwarded-Proto<br/>X-Forwarded-Port]
    end
    
    subgraph AppPod["📦 Application Pod"]
        subgraph Config["Configuration"]
            TrustedDomains[Trusted Domains:<br/>app.charn.io<br/>app.local.charn.io]
            Protocol[Protocol: HTTPS]
            TrustedProxies[Trusted Proxies:<br/>10.42.0.0/16]
        end
        
        subgraph Logic["Application Logic"]
            ReadHeaders[Read<br/>X-Forwarded-Host]
            CheckTrust{Domain<br/>Trusted?}
            DetectDomain[Detect Domain<br/>from Header]
            GenerateURLs[Generate URLs<br/>with Detected Domain]
        end
    end
    
    subgraph Response["📤 Response"]
        RespExt[URLs:<br/>https://app.charn.io/...]
        RespLoc[URLs:<br/>https://app.local.charn.io/...]
    end
    
    ReqExt -->|Host: app.charn.io| AddHeaders
    ReqLoc -->|Host: app.local.charn.io| AddHeaders
    
    AddHeaders -->|X-Forwarded-Host:<br/>app.charn.io| ReadHeaders
    AddHeaders -->|X-Forwarded-Host:<br/>app.local.charn.io| ReadHeaders
    
    ReadHeaders --> CheckTrust
    TrustedDomains -.->|Check Against| CheckTrust
    
    CheckTrust -->|✓ Yes| DetectDomain
    CheckTrust -->|✗ No| Reject[400 Bad Request]
    
    Protocol -.->|Force HTTPS| GenerateURLs
    DetectDomain --> GenerateURLs
    
    GenerateURLs -->|app.charn.io| RespExt
    GenerateURLs -->|app.local.charn.io| RespLoc
    
    style Request fill:#e1f5ff
    style Nginx fill:#4CAF50
    style AppPod fill:#2196F3
    style Config fill:#fff59d
    style Logic fill:#b2dfdb
    style Response fill:#c8e6c9
```

---

## Network Segmentation

```mermaid
graph TB
    subgraph Internet["🌐 Internet"]
        direction LR
        PublicUsers[Public Users]
    end
    
    subgraph DMZ["DMZ / Edge"]
        direction TB
        Cloudflare[Cloudflare Edge<br/>DDoS Protection<br/>WAF]
    end
    
    subgraph HomeNetwork["🏠 Home Network (Private)"]
        direction TB
        Router[Router/Firewall<br/>NAT]
        LocalDevices[Local Devices<br/>192.168.0.0/24]
    end
    
    subgraph PiHost["Raspberry Pi Host"]
        direction TB
        HostOS[Ubuntu OS]
        CloudflaredDaemon[cloudflared<br/>Outbound Only]
        
        subgraph K3sNetwork["Kubernetes Network"]
            direction TB
            
            subgraph PodNetwork["Pod Network 10.42.0.0/16"]
                IngressPods[Ingress<br/>Pods]
                AppPods[Application<br/>Pods]
                DBPods[Database<br/>Pods]
            end
            
            subgraph ServiceNetwork["Service Network 10.43.0.0/16"]
                Services[ClusterIP<br/>Services]
            end
        end
    end
    
    PublicUsers -->|HTTPS| Cloudflare
    Cloudflare -->|Tunnel<br/>Encrypted| CloudflaredDaemon
    CloudflaredDaemon -->|HTTP<br/>localhost| IngressPods
    
    LocalDevices -->|HTTPS<br/>443| Router
    Router -->|HTTPS<br/>30443| IngressPods
    
    IngressPods <-->|HTTP| Services
    Services <-->|HTTP| AppPods
    AppPods <-->|Internal| DBPods
    
    HostOS -.->|Manages| K3sNetwork
    
    style Internet fill:#e1f5ff
    style DMZ fill:#f9a825
    style HomeNetwork fill:#fff4e1
    style PiHost fill:#c8e6c9
    style K3sNetwork fill:#b2dfdb
    style PodNetwork fill:#fff59d
    style ServiceNetwork fill:#b2ebf2
```

---

## Troubleshooting Flow

```mermaid
graph TD
    Start[Issue Reported]
    
    Start --> CheckAccess{Which Access<br/>Method?}
    
    CheckAccess -->|External| ExtCheck[Check External<br/>Access]
    CheckAccess -->|Local| LocCheck[Check Local<br/>Access]
    
    ExtCheck --> DNS{DNS<br/>Resolves?}
    DNS -->|No| FixDNS[Add Cloudflare<br/>DNS Record]
    DNS -->|Yes| CFTunnel{Tunnel<br/>Connected?}
    
    CFTunnel -->|No| RestartCF[Restart<br/>cloudflared]
    CFTunnel -->|Yes| Check308{Getting<br/>308 Redirect?}
    
    Check308 -->|Yes| FixRedirect[Set ssl-redirect:<br/>false in Nginx]
    Check308 -->|No| CheckNginx[Check Nginx<br/>Logs]
    
    LocCheck --> LocalDNS{Local DNS<br/>Resolves?}
    LocalDNS -->|No| FixLocalDNS[Configure Router<br/>or Pi-hole DNS]
    LocalDNS -->|Yes| Port443{Port 443<br/>Forwarded?}
    
    Port443 -->|No| AddForward[Add Port<br/>Forward in Router]
    Port443 -->|Yes| CheckCert{Certificate<br/>Valid?}
    
    CheckCert -->|No| Port80{Port 80<br/>Open?}
    Port80 -->|No| OpenPort80[Open Port 80<br/>for Validation]
    Port80 -->|Yes| WaitCert[Wait for<br/>Cert Issuance]
    
    CheckCert -->|Yes| CheckNginx
    
    CheckNginx --> NginxOK{Nginx<br/>Responding?}
    NginxOK -->|No| RestartNginx[Restart Nginx<br/>Ingress]
    NginxOK -->|Yes| CheckIngress{Ingress<br/>Exists?}
    
    CheckIngress -->|No| CreateIngress[Create Ingress<br/>Resource]
    CheckIngress -->|Yes| CheckApp{App<br/>Responding?}
    
    CheckApp -->|No| CheckPods[Check Pod<br/>Status & Logs]
    CheckApp -->|Yes| CheckConfig{Correct<br/>Domain Config?}
    
    CheckConfig -->|No| FixAppConfig[Configure App<br/>Trusted Domains]
    CheckConfig -->|Yes| Success[✓ Working]
    
    FixDNS --> Success
    RestartCF --> Success
    FixRedirect --> Success
    FixLocalDNS --> Success
    AddForward --> Success
    WaitCert --> Success
    RestartNginx --> Success
    CreateIngress --> Success
    FixAppConfig --> Success
    CheckPods --> FixApp[Fix Application<br/>Issue]
    FixApp --> Success
    
    style Start fill:#e1f5ff
    style Success fill:#4CAF50
    style DNS fill:#fff59d
    style CFTunnel fill:#fff59d
    style Check308 fill:#fff59d
    style CheckApp fill:#fff59d
```

---

## Usage Instructions

### Viewing Diagrams

These Mermaid diagrams can be viewed in:
1. **GitHub/GitLab** - Renders automatically in markdown
2. **VS Code** - Install Mermaid preview extension
3. **Online** - https://mermaid.live
4. **Documentation sites** - Most support Mermaid

### Diagram Descriptions

- **High-Level Overview**: 30,000-foot view of the entire system
- **External Access Flow**: Detailed sequence of external requests
- **Local Access Flow**: Detailed sequence of local requests
- **Certificate Management**: How certificates are issued and distributed
- **Nginx Ingress Routing**: How requests are routed to services
- **Complete System Architecture**: Every component and connection
- **Application Configuration**: How apps auto-detect domains
- **Network Segmentation**: Security zones and network isolation
- **Troubleshooting Flow**: Decision tree for problem resolution

### Customization

To customize these diagrams:
1. Copy the Mermaid code
2. Paste into https://mermaid.live
3. Edit as needed
4. Export as PNG/SVG or copy updated markdown

---

**Document Version:** 1.0  
**Created:** November 2025  
**Format:** Mermaid Diagrams  
**Purpose:** Visual documentation of hybrid network architecture