# StoreKit Setup

Products (create these in App Store Connect under bundle `com.petcare360.app`):

| Product ID | Type | Target US price |
|---|---|---|
| `com.petcare360.premium.monthly` | Auto-renewable subscription | $4.99 / month |
| `com.petcare360.premium.yearly` | Auto-renewable subscription | $29.99 / year |

Put both in one subscription group ("Premium"). The app reads the live price
from StoreKit (`Product.displayPrice`); the prices above are targets only.

Local testing: the scheme is bound to `PetCare360/PetCare360.storekit`, which
contains both products at the target prices. Entitlement is granted only from
verified `Transaction.currentEntitlements` — there is no debug backdoor.

Free vs Premium (enforced via `EntitlementPolicy` + paywall gates):
- Free: 1 pet, basic reminders, basic medication tracking, basic records,
  limited documents, basic health timeline, emergency screen (always free).
- Premium: unlimited pets, household coordination and caregiver roles on this device, medication tracking and history,
  unlimited records, document scanning, expenses, insurance organizer,
  advanced charts, Emergency QR profile, advanced PDFs, recall notifications.
