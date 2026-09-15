# Billing decision for launch

## Decision

Use Creem as the merchant-of-record provider for the first paid launch.

Creem is the contractual seller for customer transactions. Creem creates the customer invoices, handles indirect-tax calculation and remittance, manages payment disputes, and provides payout reverse invoices for the business's accounting records. Safernotes receives signed webhook events and stores only the resulting subscription state.

## Why Creem

Creem fits the launch constraints:

- merchant-of-record model with customer invoices issued by Creem
- flat advertised fee of 3.9% plus USD 0.40 per successful transaction
- no monthly platform fee
- VAT and sales-tax handling included
- subscriptions, hosted checkout, dunning, and customer portal included
- free SEPA payouts for EU accounts through Stripe Connect
- reverse invoice available for each payout

Creem is a newer provider than Paddle or Stripe. Before launch, account approval, invoice output, EUR settlement, refund behavior, data exports, and the data processing agreement must be verified using the test and live environments.

## Pricing strategy

Launch annual-first because the fixed fee is material on low-value transactions:

- Free: 0 EUR
- Essential: 1.50 EUR monthly equivalent, billed yearly at 18 EUR
- Pro: 5 EUR monthly equivalent, billed yearly at 60 EUR

Essential and Pro are the only paid self-service plans exposed in the catalogue and accepted by the checkout API. Historical internal Team and Enterprise policies are not purchasable or displayed.

Do not offer Essential as a 1.50 EUR monthly card transaction. Monthly plans, if added later, must be priced higher than one twelfth of the annual plan.

## Backend configuration

Creem Test Mode uses a separate API host, API key, product catalog, and webhook configuration:

```env
BILLING_PROVIDER=creem
BILLING_API_KEY=creem_test_...
BILLING_API_BASE_URL=https://test-api.creem.io/v1
BILLING_PRODUCT_IDS={"essential":"prod_...","pro":"prod_..."}
BILLING_SUCCESS_URL=https://app.safernotes.com/?billing=success
BILLING_WEBHOOK_SECRET=whsec_...
```

Production uses live keys and live product IDs:

```env
BILLING_PROVIDER=creem
BILLING_API_KEY=creem_live_...
BILLING_API_BASE_URL=https://api.creem.io/v1
BILLING_PRODUCT_IDS={"essential":"prod_...","pro":"prod_..."}
BILLING_SUCCESS_URL=https://app.safernotes.com/?billing=success
BILLING_WEBHOOK_SECRET=whsec_...
```

The checkout request sends:

- the configured Creem `product_id`
- a unique internal `request_id`
- the account owner's email to prefill checkout
- signed webhook metadata containing only `tenant_id` and `plan`
- the configured success URL

The customer portal is generated dynamically with `POST /v1/customers/billing` using the Creem customer ID stored from webhooks.

The web/PWA client exposes checkout and portal links. Native App Store and Google Play builds show only the current subscription state; they contain no paid-plan catalogue, prices, purchase calls to action, external billing links, or portal links.

## Webhooks

Register this endpoint in both Creem Test Mode and production:

```text
https://api.safernotes.com/api/v1/billing/webhook
```

Subscribe to:

- `checkout.completed`
- `subscription.active`
- `subscription.paid`
- `subscription.update`
- `subscription.scheduled_cancel`
- `subscription.past_due`
- `subscription.unpaid`
- `subscription.canceled`
- `subscription.expired`
- `subscription.paused`
- `subscription.trialing`
- `refund.created`
- `dispute.created`

Creem signs the exact request body with HMAC-SHA256 and sends the hex digest in `creem-signature`. The backend verifies this header before parsing or processing the event and responds with HTTP 200. Billing events are stored idempotently using the Creem event ID.

Access remains active for `subscription.scheduled_cancel`, `subscription.past_due`, and `subscription.expired` while Creem can still recover payment. Cancellation, pause, unpaid, refund, and dispute events downgrade the workspace to Free.

## Accounting and privacy launch gates

Before accepting live payments:

- verify a customer invoice and payout reverse invoice with an Austrian Steuerberater
- confirm treatment of Creem self-billing/reverse invoices, reverse charge, UID, and Kleinunternehmer status
- retain payout reverse invoices, statements, fee records, and transaction exports
- sign or download the applicable data processing agreement
- update the privacy policy with Creem, payment-data categories, purposes, retention, and international-transfer details
- state clearly that encrypted note content and encryption keys are never sent to Creem
- keep webhook metadata limited to tenant ID and plan
- validate refunds, disputes, cancellations, failed renewals, and portal access in Test Mode

## Primary sources

- Checkout API: https://docs.creem.io/api-reference/endpoint/create-checkout
- Webhooks and event payloads: https://docs.creem.io/code/webhooks
- Customer portal: https://docs.creem.io/features/customer-portal
- Test Mode: https://docs.creem.io/getting-started/test-mode
- Pricing and payouts: https://docs.creem.io/merchant-of-record/finance/payouts
- Merchant-of-record terms and invoicing: https://www.creem.io/terms
