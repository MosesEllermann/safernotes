# Billing decision for launch

## Recommendation

Use Paddle as the merchant-of-record provider for the first paid launch.

This avoids running our own invoice numbering, VAT collection, tax remittance, payment disputes, and buyer billing support at launch. The app receives webhook events and only stores the resulting subscription state.

## Why not Stripe first

Stripe has lower card processing fees in the EEA, but Stripe alone keeps more accounting and tax responsibility on the business. Stripe Billing, Invoicing, and Tax can help, but invoice-number integration with an existing accounting flow still needs an explicit finance process.

Stripe is a good later option when payment volume is high enough that lower transaction fees outweigh the extra accounting and tax work.

## Why Paddle first

Paddle fits the current constraints:

- no monthly platform fee
- merchant-of-record model
- VAT/sales-tax handling included
- buyer billing support included
- payouts handled by the provider
- stronger SaaS subscription, checkout, invoicing, and customer portal tooling

Launch pricing should be annual-first because merchant-of-record pricing includes a fixed fee per transaction. This keeps the advertised monthly price competitive while avoiding twelve fixed transaction fees per year.

The current backend exposes:

- Free: 0 EUR
- Essential: 1.50 EUR monthly equivalent, billed yearly at 18 EUR
- Pro: 5 EUR monthly equivalent, billed yearly at 60 EUR
- Team: 15 EUR monthly or 150 EUR yearly per workspace
- Enterprise: custom

Monthly plans can be added later, but should be priced higher than the yearly equivalent. For launch, yearly billing is the default path.

## Compliance notes

For production, complete these before accepting live payments:

- sign a data processing agreement with the selected billing provider
- update the privacy policy with billing provider, payment data categories, and international transfer details
- document that note contents remain zero-knowledge encrypted and are not sent to the billing provider
- keep billing webhooks minimal: tenant id, plan, subscription status, customer id, subscription id
- confirm the final tax/accounting setup with a Steuerberater

## Backend configuration

Use Paddle transaction checkouts first:

```env
BILLING_PROVIDER=paddle
BILLING_API_KEY=pdl_sdbx_apikey_...
BILLING_API_BASE_URL=https://sandbox-api.paddle.com
BILLING_PRICE_IDS={"essential":"pri_...","pro":"pri_...","team":"pri_..."}
BILLING_PORTAL_URL=
BILLING_WEBHOOK_SECRET=change-me
```

The checkout endpoint creates a Paddle transaction with `collection_mode=automatic`, the selected Paddle `price_id`, and minimal `custom_data`: tenant id, plan, and owner email. Hosted checkout URLs remain supported as a fallback for early testing:

```env
BILLING_CHECKOUT_URLS={"essential":"https://checkout.example/essential","pro":"https://checkout.example/pro","team":"https://checkout.example/team"}
```

Webhooks can be sent back to:

```text
/api/v1/billing/webhook
```

The backend supports Paddle Billing's `Paddle-Signature` header and keeps the generic `X-Billing-Signature` header for internal testing.

## Sources checked

- Paddle pricing and merchant-of-record details: https://www.paddle.com/pricing
- Paddle webhooks: https://developer.paddle.com/webhooks/
- Notesnook pricing benchmark: https://notesnook.com/pricing
- Stripe pricing: https://stripe.com/en-de/pricing
