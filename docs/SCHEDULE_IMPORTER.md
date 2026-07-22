# Schedule importer workflow

1. Paste rows or upload CSV; parse entirely into a staging preview.
2. Select source timezone and attribution.
3. Map origin/destination to `airports`, retaining separate reference, simulator, navigation, and display codes.
4. Normalize local times, weekday arrays, probability, and variability.
5. Validate spoken/tracking/display callsigns and flag conflicts.
6. Detect duplicates by template identity and prospective departure.
7. Approve rows individually, then insert `schedule_templates` transactionally.

The importer never scrapes the reference site or creates a runtime dependency on it.
