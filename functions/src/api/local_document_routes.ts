import express, { Router } from "express";

import { inspectUploadedObject } from "../upload_inspection";
import { detectContentType } from "./content_inspection";
import { Problem } from "./errors";
import {
  downloadObject,
  hasValidLocalDocumentCapability,
  uploadObject,
  usingLocalDocumentStorage,
} from "./storage";

/**
 * Development-only counterpart to Cloud Storage signed URLs.
 *
 * It is mounted only by the local API process when all LOCAL_DOCUMENT_STORAGE
 * variables are present. Cloud Functions never use these routes. Capabilities
 * are signed by the API, expire quickly and are bound to the upload content
 * type, so the mobile client still has no general local-file access.
 */
export function localDocumentRoutes(): Router {
  const r = Router();

  r.put(
    "/upload",
    express.raw({ type: () => true, limit: "25mb" }),
    async (req, res, next) => {
      try {
        if (!usingLocalDocumentStorage()) {
          throw Problem.notFound("NO_ROUTE", "Not found.");
        }
        const contentType = req.header("content-type") ?? "";
        const { path: objectPath, expires, signature, contentType: signedType } = req.query;
        if (
          typeof signedType !== "string" ||
          signedType !== contentType ||
          !hasValidLocalDocumentCapability("PUT", objectPath, expires, signature, contentType)
        ) {
          throw Problem.forbidden("UPLOAD_CAPABILITY_INVALID", "This upload link is invalid or expired.");
        }
        if (!Buffer.isBuffer(req.body) || req.body.length === 0) {
          throw Problem.validation("The file appears to be empty.", { file: "empty" });
        }

        await uploadObject(objectPath, req.body, contentType);
        await inspectUploadedObject(objectPath);
        res.status(204).end();
      } catch (error) {
        next(error);
      }
    }
  );

  r.get("/download", async (req, res, next) => {
    try {
      if (!usingLocalDocumentStorage()) {
        throw Problem.notFound("NO_ROUTE", "Not found.");
      }
      const { path: objectPath, expires, signature } = req.query;
      if (!hasValidLocalDocumentCapability("GET", objectPath, expires, signature)) {
        throw Problem.forbidden("DOWNLOAD_CAPABILITY_INVALID", "This download link is invalid or expired.");
      }
      const data = await downloadObject(objectPath);
      res.type(detectContentType(data) ?? "application/octet-stream");
      res.send(data);
    } catch (error) {
      next(error);
    }
  });

  return r;
}
