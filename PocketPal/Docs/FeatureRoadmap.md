# PocketPal Advanced Features Roadmap

## Overview

This document outlines the implementation roadmap for adding advanced expense management features to PocketPal, targeting both personal users and small businesses for tax submission purposes.

## Current Status: Phase 1 Complete

### Phase 1: Foundation & Dashboard

**Status: COMPLETED**

| Task | File | Description |
|------|------|-------------|
| New Domain Models | `Domain/Models/ConnectionModels.swift` | `ConnectionProvider`, `ExpenseType`, `TaxCategory`, `SyncStatus` enums |
| Receipt Model Updates | `Persistence/Receipt.swift` | Added expense classification and source tracking fields |
| Connection Model | `Persistence/Connection.swift` | SwiftData model for connected accounts |
| SyncLog Model | `Persistence/SyncLog.swift` | SwiftData model for sync history |
| Keychain Service | `Services/Security/KeychainService.swift` | Secure OAuth token storage |
| Dashboard View | `Features/Dashboard/DashboardView.swift` | New home screen with stats and connections |
| Tab Navigation | `App/RootTabView.swift` | Dashboard added as first tab |

---

## Upcoming Phases

### Phase 2: Email Invoice Scanning

**Status: NOT STARTED**

Enable users to connect their email accounts and automatically import receipts from invoices.

**Files to Create:**
```
Services/Email/
├── EmailServiceProtocol.swift    # Protocol for email providers
├── GmailService.swift            # Gmail API integration
├── MicrosoftGraphService.swift   # Outlook/Microsoft Graph API
└── InvoiceDetectionService.swift # Detect invoices in emails

Domain/UseCases/
└── ImportEmailReceiptUseCase.swift # Email-to-receipt workflow
```

**Key Features:**
- OAuth 2.0 authentication for Gmail and Outlook
- Email scanning with invoice detection keywords
- Attachment extraction (PDF, images)
- Email body parsing for transaction details

**Dependencies:**
- Google Sign-In SDK
- GTMAppAuth (Gmail OAuth)
- MSAL (Microsoft Authentication Library)

---

### Phase 3: E-commerce Platform Integration

**Status: NOT STARTED**

Connect to online shopping platforms to fetch order history and receipts.

**Files to Create:**
```
Services/Ecommerce/
├── EcommerceServiceProtocol.swift # Protocol for e-commerce providers
├── eBayService.swift              # eBay Buy/Sell API
├── TaobaoService.swift            # Alibaba Open Platform API
├── AmazonService.swift            # Amazon Pay API (limited)
└── TemuService.swift              # Email-based detection (no public API)

Domain/UseCases/
└── ImportEcommerceReceiptUseCase.swift # Order-to-receipt workflow
```

**Provider API Status:**
| Provider | API | Notes |
|----------|-----|-------|
| eBay | Full API | OAuth 2.0, complete order history |
| Gmail/Outlook | Email Detection | Best for Temu, Amazon |
| Amazon | Limited | Pay API or email detection |
| Taobao | Limited | Alibaba Open Platform |
| Temu | None | Email detection only |

---

### Phase 4: Enhanced Expense Management

**Status: NOT STARTED**

Add business expense tracking and tax reporting capabilities.

**Files to Create:**
```
Services/
├── ExpenseClassificationService.swift # Auto-categorize expenses
└── ExportService.swift               # CSV, PDF, Excel export

Features/Reports/
└── TaxReportView.swift               # Tax summary and export
```

**Key Features:**
- Personal vs Business expense classification
- Tax category suggestions based on merchant
- Quarterly/annual tax summaries
- Export for tax submission (PDF)
- Export for accounting (CSV, Excel)

---

### Phase 5: Connection Management UI

**Status: NOT STARTED**

User interface for managing connected accounts.

**Files to Create:**
```
Features/Connections/
├── ConnectionListView.swift      # List all connections
├── EmailConnectionView.swift     # Email OAuth flow
└── PlatformConnectionView.swift  # E-commerce OAuth flow
```

**Features:**
- Connection status indicators
- Manual sync triggers
- Disconnect/reconnect options
- Sync history view

---

### Phase 6: Settings & Premium Features

**Status: NOT STARTED**

Update settings and implement premium feature gating.

**Files to Update:**
```
Features/Settings/SettingsView.swift  # Add new sections

Services/
└── PremiumService.swift              # Premium feature checks
```

**Settings Sections:**
- Connected Accounts
- Sync Preferences
- Tax Settings (business info, tax year)
- Export Defaults
- Premium Features indicators

---

## Architecture Decisions

### Security
- All OAuth tokens stored in Keychain with `kSecAttrAccessibleAfterFirstUnlock`
- Biometric protection option for sensitive operations
- No passwords stored - OAuth only

### Data Privacy
- Email content processed locally (no cloud processing)
- User consent required for each connection
- Clear data retention policy
- Option to delete synced data without disconnecting

### Model Changes

**Receipt Model Extensions:**
```swift
// Expense Classification
var expenseTypeRawValue: String      // personal, business, reimbursable
var taxCategoryRawValue: String?     // deductible, travel, meals, etc.

// Source Tracking
var sourceProviderRawValue: String?  // gmail, amazon, ebay, etc.
var sourceOrderID: String?           // E-commerce order reference
var sourceEmailID: String?           // Email message ID
```

**New Models:**
- `Connection` - Tracks connected accounts
- `SyncLog` - Tracks sync history per connection

---

## Testing Strategy

### Unit Tests
- InvoiceDetectionService keyword matching
- KeychainService operations (mock Keychain)
- ExportService generation

### Integration Tests
- Email service mock with test fixtures
- E-commerce API mock using URLProtocol
- End-to-end import flow

### UI Tests
- Connection flow automation
- Dashboard loading states

---

## Timeline Estimate

| Phase | Duration | Priority |
|-------|----------|----------|
| Phase 1: Foundation | 2 weeks | DONE |
| Phase 2: Email Scanning | 3 weeks | HIGH |
| Phase 3: E-commerce | 3 weeks | MEDIUM |
| Phase 4: Expense Management | 2 weeks | MEDIUM |
| Phase 5: Connection UI | 2 weeks | HIGH |
| Phase 6: Settings/Premium | 1 week | LOW |

**Total Estimated: 12-13 weeks** (flexible, incremental delivery)

---

## Success Metrics

1. **Email Scanning**: 90%+ invoice detection accuracy
2. **E-commerce**: Successfully import from at least 2 platforms
3. **Tax Reports**: Generate compliant PDF reports
4. **User Adoption**: 50% of users connect at least one account

---

## Dependencies

### External SDKs
- Google Sign-In SDK
- GTMAppAuth
- MSAL (Microsoft Authentication Library)

### System Requirements
- iOS 17.0+
- macOS 14.0+
- Swift 5.0+

---

## Notes

- **Temu**: No public API available - must rely on email detection from order confirmations
- **Amazon**: Limited API access - email detection may be primary method
- **Cloud Sync**: Architecture supports future CloudKit integration
- **Paid Features**: Consider gating e-commerce integrations and tax reports for premium tier
