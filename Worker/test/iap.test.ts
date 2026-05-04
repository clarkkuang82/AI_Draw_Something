import { describe, it, expect } from "vitest";
import { lookupProduct } from "../src/iap/products.js";

describe("IAP product catalog", () => {
  it("knows the four configured product ids", () => {
    expect(lookupProduct("com.aidraw.coins.20")?.kind).toBe("consumable");
    expect(lookupProduct("com.aidraw.coins.100")?.credits).toBe(100);
    expect(lookupProduct("com.aidraw.coins.500")?.credits).toBe(500);
    expect(lookupProduct("com.aidraw.pro.month")?.kind).toBe("subscription");
  });

  it("rejects unknown ids", () => {
    expect(lookupProduct("com.evil.unlimited")).toBeNull();
    expect(lookupProduct("")).toBeNull();
  });
});
