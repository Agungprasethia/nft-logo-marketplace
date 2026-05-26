# LEO NFT Marketplace — Required Firestore Indexes

This document lists all Firestore indexes required for the LEO NFT Marketplace
to function correctly. Missing indexes will cause `failed-precondition` errors
in production.

> **Note:** The app gracefully handles missing indexes at runtime via
> `FirestoreErrorHandler`, but indexes should still be created for optimal
> query performance.

---

## Standard Collection Indexes

### `nfts`

| Fields | Order | Purpose |
|--------|-------|---------|
| `status` (ASC) | — | Filter NFTs by status (pending/approved/rejected) |
| `creatorId` (ASC), `createdAt` (DESC) | Composite | Creator's NFTs sorted by time |
| `ownerId` (ASC), `createdAt` (DESC) | Composite | Owner's collection sorted by time |
| `isActive` (ASC) | — | Filter active/inactive NFTs |
| `auctionCreated` (ASC) | — | Count auction-created NFTs |
| `imageUrl` (ASC) | — | Ownership verification by image URL |
| `ownerWallet` (ASC) | — | Lookup by wallet address |

### `auctions`

| Fields | Order | Purpose |
|--------|-------|---------|
| `status` (ASC), `createdAt` (DESC) | Composite | Filter auctions by status |
| `sellerId` (ASC), `createdAt` (DESC) | Composite | Seller's auctions |
| `highestBidderId` (ASC), `createdAt` (DESC) | Composite | Bidder's won auctions |

### `reports`

| Fields | Order | Purpose |
|--------|-------|---------|
| `status` (ASC) | — | Filter pending/resolved reports |
| `tokenId` (ASC), `reporterWallet` (ASC), `status` (ASC) | Composite | Duplicate report prevention |
| `createdAt` (DESC) | — | Sort reports by time |

### `appeals`

| Fields | Order | Purpose |
|--------|-------|---------|
| `tokenId` (ASC) | — | Look up appeals by NFT |
| `creatorWallet` (ASC) | — | Look up appeals by creator |
| `createdAt` (DESC) | — | Sort appeals by time |

### `transactions`

| Fields | Order | Purpose |
|--------|-------|---------|
| `type` (ASC), `status` (ASC) | Composite | Completed sales count |

### `users`

| Fields | Order | Purpose |
|--------|-------|---------|
| `role` (ASC) | — | Admin role verification |
| `walletAddress` (ASC) | — | User lookup by wallet |

### `notifications` (subcollection of `users`)

| Fields | Order | Purpose |
|--------|-------|---------|
| `isRead` (ASC), `createdAt` (DESC) | Composite | Unread notifications sorted by time |
| `createdAt` (DESC) | — | All notifications sorted by time |

---

## Collection Group Indexes

These are **critical** and must be explicitly created in the Firebase Console.

### `bids` (Collection Group)

The `bids` subcollection lives under `nfts/{tokenId}/bids/{bidId}`.

| Fields | Order | Purpose |
|--------|-------|---------|
| `bidderWallet` (ASC) | — | `getUserParticipatedBidsStream()` — find all bids by a wallet across all NFTs |

> **Important:** Collection Group indexes must be created manually in the
> Firebase Console under **Firestore → Indexes → Collection Group**.
> Standard composite indexes do NOT cover collection group queries.

---

## How to Create Missing Indexes

1. Open the [Firebase Console](https://console.firebase.google.com)
2. Navigate to **Firestore Database → Indexes**
3. Click **Create Index**
4. For collection group indexes, select **Collection Group** scope
5. Enter the collection name and field configuration

Alternatively, when running in debug mode, the app prints the exact
Firebase Console URL for any missing index. Click that URL to auto-create
the index with the correct configuration.

---

## Verification

After creating all indexes, verify with:

```bash
flutter run
```

- Open each screen (Home, Profile/Bids, Admin Dashboard, Notifications)
- Confirm no "Marketplace Data Preparing" fallback states appear
- Check debug console for any remaining index warnings
