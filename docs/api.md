# REST API

Bearer-token-authed REST API at `/api/v1/*` for mobile clients, n8n,
Home Assistant, anything that speaks HTTP.

## Authentication

Get a token by exchanging email + password:

```bash
curl -sX POST https://pantria.your-host/api/v1/sessions \
     -d 'email=demo@homestead.local&password=password123'
# => { "token": "...", "user": { "id": 1, "name": "Demo", "email": "..." } }
```

Stash the token; every subsequent request adds:

```
Authorization: Bearer <token>
```

Tokens are per-user, never expire by themselves, and can be revoked from
the user's account page. They identify the user; the single household this
instance serves (`Household.current`) is the scope for every API call. The
old `X-Household-Id` header is no longer used.

## Endpoints

### Catalog

| Method | Path                                | Description                                              |
| ------ | ----------------------------------- | -------------------------------------------------------- |
| GET    | `/api/v1/products`                  | List products in current household                       |
| POST   | `/api/v1/products`                  | Create a product                                         |
| GET    | `/api/v1/products/lookup?barcode=X` | Look up a barcode (local → external waterfall)           |
| GET    | `/api/v1/stores`                    | List stores                                              |
| POST   | `/api/v1/stores`                    | Create a store                                           |
| GET    | `/api/v1/prices?product_id=X`       | Price history for a product                              |
| POST   | `/api/v1/prices`                    | Record a price                                           |

### Inventory

| Method | Path                                 | Description                                  |
| ------ | ------------------------------------ | -------------------------------------------- |
| GET    | `/api/v1/storage_items`              | List storage rows                            |
| POST   | `/api/v1/storage_items`              | Add to storage                               |
| PATCH  | `/api/v1/storage_items/:id`          | Update qty / location / expires              |
| DELETE | `/api/v1/storage_items/:id`          | Remove                                       |
| GET    | `/api/v1/grocery_items`              | List grocery rows                            |
| POST   | `/api/v1/grocery_items`              | Add (freeform or product-linked)             |
| PATCH  | `/api/v1/grocery_items/:id`          | Update                                       |
| POST   | `/api/v1/grocery_items/scan_purchase`| Mark as bought by scanning EAN at the till   |

### Receipts

| Method | Path                                  | Description                                              |
| ------ | ------------------------------------- | -------------------------------------------------------- |
| POST   | `/api/v1/receipts`                    | Upload a receipt for OCR (multipart `image=`)            |
| POST   | `/api/v1/receipts?inline=1`           | Upload + run OCR synchronously                           |
| GET    | `/api/v1/receipts/:id`                | Receipt + parsed lines                                   |
| POST   | `/api/v1/receipts/:id/confirm`        | Apply user's choices (same JSON shape as the web form)   |
| POST   | `/api/v1/receipts/:id/reprocess`      | Re-run OCR                                               |

### Inbound email

| Method | Path                                         | Description                                       |
| ------ | -------------------------------------------- | ------------------------------------------------- |
| GET    | `/api/v1/inbound_emails`                     | List the caller's sources + per-source health     |
| POST   | `/api/v1/inbound_emails/poll`                | Drain all of them                                 |
| POST   | `/api/v1/inbound_emails/:id/poll`            | Drain one specific source                         |

## Examples

```bash
TOKEN="paste-here"

# 1. Look up a barcode (local → OpenFoodFacts → Marktguru)
curl -s "https://pantria.your-host/api/v1/products/lookup?barcode=4006381333924" \
     -H "Authorization: Bearer $TOKEN"

# 2. Upload a receipt + run OCR synchronously
curl -s "https://pantria.your-host/api/v1/receipts?inline=1" \
     -H "Authorization: Bearer $TOKEN" \
     -F image=@/path/to/receipt.jpg

# 3. Mark a needed grocery item as purchased by scanning its barcode
curl -sX POST https://pantria.your-host/api/v1/grocery_items/scan_purchase \
     -H "Authorization: Bearer $TOKEN" \
     -d 'barcode=4006381333924'

# 4. Trigger an inbound-email drain (e.g. from n8n on a cron schedule)
curl -sX POST https://pantria.your-host/api/v1/inbound_emails/poll \
     -H "Authorization: Bearer $TOKEN"
```

## Response shape

JSON only, snake_case, `application/json` content-type. Errors come
back as `{ "error": "<message>" }` with an appropriate 4xx / 5xx code.

```json
{
  "data": {
    "id": 42,
    "name": "Vollmilch 1L",
    "brand": "Bio Wiesengold",
    "barcode": "4006381333924",
    "unit": "l",
    "storage": [
      { "id": 7, "quantity": 2, "location": "fridge", "expires_on": "2026-05-13" }
    ]
  }
}
```

## Source

- Controllers: [`app/controllers/api/v1/`](https://github.com/SGraef/Homestead/tree/main/app/controllers/api/v1)
- Routes: [`config/routes.rb`](https://github.com/SGraef/Homestead/blob/main/config/routes.rb) (`namespace :api`)
- Auth: `ApiToken` model + `Api::V1::BaseController#authenticate_bearer!`
