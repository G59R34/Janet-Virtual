"use client";

import { useRouter } from "next/navigation";
import { useState } from "react";

type Person = {
  id: string;
  display_name: string;
  email: string;
};

export function DeleteUserAction({ person }: { person: Person }) {
  const router = useRouter();
  const [pending, setPending] = useState(false);
  const [error, setError] = useState("");

  async function removeUser() {
    const confirmed = window.confirm(
      `Permanently delete ${person.display_name}'s account (${person.email})? This cannot be undone.`,
    );
    if (!confirmed) return;

    setPending(true);
    setError("");
    try {
      const response = await fetch(`/api/admin/users/${person.id}`, {
        method: "DELETE",
      });
      const result = (await response.json()) as { error?: string };
      if (!response.ok) {
        throw new Error(result.error ?? "Unable to delete account");
      }
      router.refresh();
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : "Unable to delete account");
    } finally {
      setPending(false);
    }
  }

  return (
    <span className={`admin-action ${error ? "has-error" : ""}`}>
      <button
        className="mini-button danger"
        type="button"
        disabled={pending}
        onClick={removeUser}
        title={error || undefined}
      >
        {pending ? "Deleting…" : "Delete user"}
      </button>
      {error && <small role="alert">{error}</small>}
    </span>
  );
}
