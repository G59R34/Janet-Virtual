import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { createClient } from "@supabase/supabase-js";

function envValue(name) { const line = readFileSync(resolve(".env"), "utf8").split(/\r?\n/).find((candidate) => candidate.startsWith(`${name}=`)); return line?.slice(name.length + 1).replace(/^['"]|['"]$/g, ""); }
const url = envValue("NEXT_PUBLIC_SUPABASE_URL");
const serviceRoleKey = envValue("SUPABASE_SERVICE_ROLE_KEY");
if (!url || !serviceRoleKey) throw new Error("NEXT_PUBLIC_SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are required in .env");
const storage = createClient(url, serviceRoleKey, { auth: { autoRefreshToken: false, persistSession: false } }).storage;
const bucket = "crew-downloads";
const artifacts = [
  { local: "JCars/src-tauri/target/release/bundle/msi/JCars_0.3.1_x64_en-US.msi", remote: "jcars/0.3.1/JCars_0.3.1_x64_en-US.msi", contentType: "application/x-msi" },
  { local: "JCars/src-tauri/target/release/bundle/nsis/JCars_0.3.1_x64-setup.exe", remote: "jcars/0.3.1/JCars_0.3.1_x64-setup.exe", contentType: "application/x-msdownload" },
];
const { data: existingBucket, error: bucketError } = await storage.getBucket(bucket);
if (bucketError && !/not found/i.test(bucketError.message)) throw bucketError;
if (!existingBucket) { const { error } = await storage.createBucket(bucket, { public: false, fileSizeLimit: "15MB", allowedMimeTypes: artifacts.map((artifact) => artifact.contentType) }); if (error) throw error; }
for (const artifact of artifacts) { const { error } = await storage.from(bucket).upload(artifact.remote, readFileSync(resolve(artifact.local)), { contentType: artifact.contentType, upsert: true }); if (error) throw error; console.log(`Uploaded ${artifact.remote}`); }
