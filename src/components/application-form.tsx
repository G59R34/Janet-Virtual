"use client";

import { useState } from "react";
import { createClient } from "@/lib/supabase/client";

function applicationErrorMessage(error: { message: string; status?: number } | null) {
  if (error?.status === 429 || /rate limit/i.test(error?.message ?? "")) {
    return "Verification email is temporarily rate limited. Check your inbox before trying again; the Supabase test mail service can take up to an hour to reset.";
  }
  return error?.message ?? "Unable to create application account";
}

export function ApplicationForm() {
  const [state, setState] = useState<"idle" | "pending" | "done">("idle");
  const [message, setMessage] = useState("");

  async function submit(data: FormData) {
    setState("pending");
    setMessage("");
    const timezone = String(data.get("timezone"));
    const answers = {
      motivation: String(data.get("motivation")),
      experience: String(data.get("experience")),
      timezone,
    };
    const { data: auth, error } = await createClient().auth.signUp({
      email: String(data.get("email")),
      password: String(data.get("password")),
      options: {
        emailRedirectTo: `${window.location.origin}/auth/callback`,
        data: {
          display_name: String(data.get("displayName")),
          timezone,
          application_answers: answers,
        },
      },
    });
    if (error || !auth.user) {
      setMessage(applicationErrorMessage(error));
      setState("idle");
      return;
    }
    setState("done");
  }

  if (state === "done") {
    return (
      <div className="notice success">
        <strong>Application received.</strong>
        <p>
          Verify your email to access application status. Crew Administration
          will review your submission.
        </p>
      </div>
    );
  }

  return (
    <form className="form" action={submit}>
      <label>
        DISPLAY NAME<input name="displayName" required minLength={2} />
      </label>
      <label>
        EMAIL<input type="email" name="email" required />
      </label>
      <label>
        ACCOUNT PASSWORD
        <input type="password" name="password" required minLength={8} />
      </label>
      <label>
        TIMEZONE
        <select name="timezone">
          <option>America/Los_Angeles</option>
          <option>America/Denver</option>
          <option>UTC</option>
        </select>
      </label>
      <label>
        SIMULATION EXPERIENCE
        <input name="experience" placeholder="Aircraft, simulators, networks" />
      </label>
      <label>
        WHY JANET VIRTUAL AIRLINES?
        <textarea name="motivation" rows={4} required minLength={30} />
      </label>
      {message && <p className="form-message error" role="alert">{message}</p>}
      <button className="button primary" type="submit" disabled={state === "pending"}>
        {state === "pending" ? "Submitting…" : "Submit application"}
      </button>
    </form>
  );
}
