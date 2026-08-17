# Sekisho RevenueCat Product Spec

This is the single source of truth for App Store Connect, RevenueCat, and the
iOS app. Product identifiers are permanent once created in App Store Connect.
The prices below are the approved product target; App Store Connect still needs
to be updated separately before release.

| Purpose | Store product ID | Store type | Price | RevenueCat entitlement |
| --- | --- | --- | --- | --- |
| Sekisho Pro monthly | `com.onikun94.sekisho.pro.monthly` | Auto-renewable subscription | ¥790 / month | `premium` |
| Sekisho Pro annual | `com.onikun94.sekisho.pro.annual` | Auto-renewable subscription | ¥3,990 / year | `premium` |
| Sakura mascot outfit | `com.onikun94.sekisho.mascot.sakura` | Non-consumable purchase | ¥300 | `mascot_sakura` |

## Subscription configuration

- Subscription group display name: `Sekisho Pro`
- Introductory offer: 7-day free trial for new subscribers on both Pro products.
- The annual product is the default paywall selection.
- The annual price is approximately 58% lower than twelve monthly payments,
  following the same high-monthly / annual-anchor structure as Turning.
- The product page must use the current App Store localized price supplied by
  RevenueCat; the fallback values in the app are only for loading previews.

## RevenueCat configuration

- Register all three App Store products in the `sekisho (App Store)` app using
  the exact product IDs above. They are currently registered manually; adding
  an App Store Connect API key later enables automatic imports and price sync.
- Create entitlements `premium` and `mascot_sakura`, and attach products as in
  the table above.
- Configure the current Offering with annual and monthly packages. Create a
  `mascots` Offering containing the Sakura product.
- Add the app's public SDK key to the `REVENUECAT_API_KEY` build setting before
  uploading a build. It is a client key, not an App Store Connect private key.

## MVP boundaries

- No paid time-limit bypasses or emergency-unlock items.
- Pro unlocks weekday-specific rules and strict mode once those app features
  are implemented.
- The Sakura outfit remains available after a Pro subscription ends when it
  was purchased separately.
- Do not offer a lifetime Pro product while Pro includes recurring AI service
  costs. Reconsider only if a separate AI-free lifetime entitlement is designed.

## Character growth and cosmetic monetization roadmap

- The mascot grows through successfully keeping the user's commitments. Core
  growth progression remains available without paying.
- Additional mascots, outfits, room decorations, and item packs are sold as
  clearly priced non-consumable purchases.
- Initial price hypotheses are ¥300–¥500 for outfits, ¥800–¥1,200 for a new
  mascot, and ¥300–¥800 for decoration or item packs. These ranges require
  validation before products are registered in App Store Connect.
- Purchased cosmetics remain owned after Pro expires. Pro may additionally
  provide access to a rotating cosmetic collection while the entitlement is
  active.
- Do not sell time-limit bypasses, restriction-bypass items, randomized loot boxes,
  or paid shortcuts that undermine the digital-wellbeing commitment.
