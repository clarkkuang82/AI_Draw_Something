import { DurableObject } from "cloudflare:workers";
import { utcDayKey } from "../util.js";

export interface Entitlement {
  freeUsedToday: number;
  day: string;
  paidCredits: number;
  subscriptionExpiresAt?: number;  // unix ms
  referralCode?: string;
  referredBy?: string;
  referralsConsumed: number;
  referralCreditsEarnedThisMonth: number;
  referralMonth: string;            // "YYYY-MM"
  spendUsdToday: number;
  spendDay: string;
}

/// Deduct happens at /v1/guess entry. If the model fails, refund() reverses it.
/// Spend killswitch is rolled into this DO too — global cap is enforced via
/// a singleton `EntitlementDO.idFromName("__global__")`.
export class EntitlementDO extends DurableObject {
  override async fetch(req: Request): Promise<Response> {
    const url = new URL(req.url);
    const op = url.pathname;
    const body = req.method === "POST" ? await req.json().catch(() => ({})) : {};

    switch (op) {
      case "/get":           return Response.json(await this.load(body));
      case "/debit":         return Response.json(await this.debit(body));
      case "/refund":        return Response.json(await this.refund(body));
      case "/recordSpend":   return Response.json(await this.recordSpend(body));
      case "/setReferralCode": return Response.json(await this.setReferralCode(body));
      default: return new Response("not found", { status: 404 });
    }
  }

  private async load(body: any): Promise<Entitlement> {
    const e = await this.ctx.storage.get<Entitlement>("e");
    const today = utcDayKey();
    const month = today.slice(0, 7);
    const init: Entitlement = e ?? {
      freeUsedToday: 0,
      day: today,
      paidCredits: 0,
      referralsConsumed: 0,
      referralCreditsEarnedThisMonth: 0,
      referralMonth: month,
      spendUsdToday: 0,
      spendDay: today,
    };
    rolloverDaily(init, today);
    rolloverMonth(init, month);
    if (body?.referralCode && !init.referralCode) {
      init.referralCode = body.referralCode;
    }
    await this.ctx.storage.put("e", init);
    return init;
  }

  private async debit(body: any): Promise<{ ok: boolean; reason?: string; entitlement: Entitlement }> {
    const freeDaily = body.freeDaily ?? 3;
    const e = await this.load({});
    const now = Date.now();

    if (e.subscriptionExpiresAt && e.subscriptionExpiresAt > now) {
      // Subscriptions don't decrement counters — they get a free pass.
      return { ok: true, reason: "sub", entitlement: e };
    }
    if (e.paidCredits > 0) {
      e.paidCredits -= 1;
      await this.ctx.storage.put("e", e);
      return { ok: true, reason: "paid", entitlement: e };
    }
    if (e.freeUsedToday < freeDaily) {
      e.freeUsedToday += 1;
      await this.ctx.storage.put("e", e);
      return { ok: true, reason: "free", entitlement: e };
    }
    return { ok: false, reason: "paywall", entitlement: e };
  }

  private async refund(body: any): Promise<{ ok: boolean; entitlement: Entitlement }> {
    const e = await this.load({});
    const reason = body.reason as string | undefined;
    // Reverse exactly the bucket we charged. We don't pull credits back into
    // a subscription bucket because they were never debited.
    if (reason === "free" && e.freeUsedToday > 0) e.freeUsedToday -= 1;
    if (reason === "paid") e.paidCredits += 1;
    await this.ctx.storage.put("e", e);
    return { ok: true, entitlement: e };
  }

  private async recordSpend(body: any): Promise<{ ok: boolean; entitlement: Entitlement; over: boolean }> {
    const e = await this.load({});
    const today = utcDayKey();
    if (e.spendDay !== today) {
      e.spendDay = today;
      e.spendUsdToday = 0;
    }
    const usd: number = Number(body.usd) || 0;
    e.spendUsdToday += usd;
    const cap: number = Number(body.cap) || Infinity;
    const over = e.spendUsdToday > cap;
    await this.ctx.storage.put("e", e);
    return { ok: true, entitlement: e, over };
  }

  private async setReferralCode(body: any): Promise<{ ok: boolean; entitlement: Entitlement }> {
    const e = await this.load({});
    if (typeof body?.code === "string" && body.code.length > 0) {
      e.referralCode = body.code;
      await this.ctx.storage.put("e", e);
    }
    return { ok: true, entitlement: e };
  }
}

function rolloverDaily(e: Entitlement, today: string) {
  if (e.day !== today) {
    e.day = today;
    e.freeUsedToday = 0;
  }
}

function rolloverMonth(e: Entitlement, month: string) {
  if (e.referralMonth !== month) {
    e.referralMonth = month;
    e.referralCreditsEarnedThisMonth = 0;
  }
}
