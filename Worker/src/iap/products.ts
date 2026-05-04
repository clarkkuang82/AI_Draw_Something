/// Catalog of IAP products. Must match the App Store Connect configuration.
/// Matched against the JWS's `productId` field — anything not in this map
/// is rejected.

export type ProductKind = "consumable" | "subscription";

export interface Product {
  id: string;
  kind: ProductKind;
  /// Number of game credits. Subscriptions ignore this (they grant unlimited).
  credits: number;
}

export const PRODUCTS: Record<string, Product> = {
  "com.aidraw.coins.20": { id: "com.aidraw.coins.20", kind: "consumable", credits: 20 },
  "com.aidraw.coins.100": { id: "com.aidraw.coins.100", kind: "consumable", credits: 100 },
  "com.aidraw.coins.500": { id: "com.aidraw.coins.500", kind: "consumable", credits: 500 },
  "com.aidraw.pro.month": { id: "com.aidraw.pro.month", kind: "subscription", credits: 0 },
};

export function lookupProduct(id: string): Product | null {
  return PRODUCTS[id] ?? null;
}
