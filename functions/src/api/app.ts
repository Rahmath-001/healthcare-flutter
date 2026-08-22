import cors from "cors";
import express from "express";

import { adminRoutes } from "./admin/routes";
import { reviewRoutes } from "./admin/review_routes";
import { appointmentRoutes, noteRoutes } from "./appointments/routes";
import { medicationRoutes } from "./medications/routes";
import { prescriptionTemplateRoutes } from "./prescriptions/template_routes";
import { availabilityRoutes } from "./availability/routes";
import { authRoutes, meRoutes } from "./auth/routes";
import { sessionRoutes } from "./auth/session_routes";
import { cookieModeEnabled, webOrigins } from "./auth/refresh_cookie";
import { appointmentCreateRoutes, bookingRoutes } from "./booking/routes";
import { consentRoutes } from "./consent/routes";
import { waitlistRoutes } from "./booking/waitlist_routes";
import { consultationRoutes } from "./consultations/routes";
import { credentialRoutes } from "./credentials/routes";
import { doctorRoutes } from "./doctors/routes";
import { notificationRoutes } from "./notifications/routes";
import { problemHandler, Problem, requestId } from "./errors";
import {
  prescriptionRoutes,
  prescriptionVerifyRoutes,
} from "./prescriptions/routes";
import { providerRoutes } from "./provider/routes";
import { ratingRoutes } from "./ratings/routes";
import { recordRoutes } from "./records/routes";
import { supportRoutes } from "./support/routes";

/**
 * The MiDoctor API.
 *
 * Express rather than callable functions, deliberately: the Flutter client is
 * already built against a REST contract — `/v1/...` paths, `Bearer` tokens,
 * RFC 9457 error bodies, a `TOKEN_STALE` refresh-and-replay interceptor. Using
 * `onCall` would have meant rewriting `ApiClient`, `AuthInterceptor` and every
 * repository to speak Firebase's envelope instead. This way the client is
 * unchanged and the vendor stays swappable.
 */
export interface AppDependencies {
  /** MiDoctor access-token signing key. */
  secret: () => string;
  /** 100ms credentials. Absent means video consultations are unconfigured. */
  hmsAccessKey?: () => string | undefined;
  hmsSecret?: () => string | undefined;
}

export function buildApp(deps: AppDependencies | (() => string)) {
  // Accepts the original bare-secret form so existing callers and tests keep
  // working while the dependency set grows.
  const resolved: AppDependencies =
    typeof deps === "function" ? { secret: deps } : deps;
  const secret = resolved.secret;
  const app = express();

  app.disable("x-powered-by");
  app.use(express.json({ limit: "1mb" }));
  app.use(requestId);

  // The mobile app is not a browser origin, so CORS exists only for the Flutter
  // web build. Kept permissive on methods but explicit about headers.
  //
  // Credentialed CORS is opt-in via `WEB_ORIGINS`, and when it is on the origin
  // list is an explicit allow-list rather than a reflection of whatever the
  // caller sent. `origin: true` reflects the request origin, which is harmless
  // while `credentials` is false and is a standing invitation to every site on
  // the internet the moment it is not — the browser would attach the refresh
  // cookie to their cross-origin request and hand them the response.
  app.use(
    cookieModeEnabled()
      ? cors({
          origin: webOrigins(),
          credentials: true,
          allowedHeaders: ["Authorization", "Content-Type", "x-request-id"],
          exposedHeaders: ["x-request-id", "retry-after"],
        })
      : cors({
          origin: true,
          credentials: false,
          allowedHeaders: ["Authorization", "Content-Type", "x-request-id"],
          exposedHeaders: ["x-request-id", "retry-after"],
        })
  );

  app.get("/v1/health", (_req, res) => res.json({ ok: true }));

  // Before the auth router, whose own paths are literals but which
  // owns the /v1/auth prefix.
  app.use("/v1/auth/sessions", sessionRoutes(secret));
  app.use("/v1/auth", authRoutes(secret));
  app.use("/v1/me", meRoutes(secret));
  app.use("/v1/doctors", doctorRoutes(secret));
  app.use("/v1/consent", consentRoutes(secret));
  app.use("/v1/provider", providerRoutes(secret));
  app.use("/v1/admin", adminRoutes(secret));
  app.use("/v1/review", reviewRoutes(secret));
  app.use("/v1/records", recordRoutes(secret));
  app.use("/v1/availability", availabilityRoutes(secret));
  app.use("/v1/credentials", credentialRoutes(secret));
  app.use("/v1/ratings", ratingRoutes(secret));
  app.use("/v1/notifications", notificationRoutes(secret));
  app.use("/v1/waitlist", waitlistRoutes(secret));
  app.use("/v1/notes", noteRoutes(secret));
  // Before the prescriptions router: its `/:id` route would otherwise
  // match the literal path "templates".
  app.use("/v1/prescriptions/templates", prescriptionTemplateRoutes(secret));
  app.use("/v1/medications", medicationRoutes(secret));
  app.use("/v1/support/tickets", supportRoutes(secret));
  app.use("/v1/prescriptions", prescriptionRoutes(secret));
  // Unauthenticated: a pharmacist verifying a QR code holds no token.
  app.use("/v1/rx", prescriptionVerifyRoutes());
  app.use(
    "/v1/consultations",
    consultationRoutes(
      secret,
      resolved.hmsAccessKey ?? (() => undefined),
      resolved.hmsSecret ?? (() => undefined)
    )
  );

  // Slot listing and holds span /v1/doctors/:id/slots and /v1/slots/:id/hold,
  // so they mount at /v1. `doctorRoutes` above cannot swallow the slots path:
  // its own `/:id` matches a single segment only.
  app.use("/v1", bookingRoutes(secret));

  // Two routers share this prefix, split by method rather than by path —
  // creation lives with booking's transaction logic, everything else with the
  // appointment lifecycle.
  app.use("/v1/appointments", appointmentCreateRoutes(secret));
  app.use("/v1/appointments", appointmentRoutes(secret));

  app.use((_req, _res, next) => {
    next(Problem.notFound("NO_ROUTE", "Not found."));
  });
  app.use(problemHandler);

  return app;
}
