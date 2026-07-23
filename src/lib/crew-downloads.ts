export const jcarsDownload = {
  version: "0.3.1",
  artifacts: {
    msi: { name: "JCars_0.3.1_x64_en-US.msi", path: "jcars/0.3.1/JCars_0.3.1_x64_en-US.msi", label: "MSI installer", description: "Recommended for managed Windows installations.", size: "3.2 MB" },
    exe: { name: "JCars_0.3.1_x64-setup.exe", path: "jcars/0.3.1/JCars_0.3.1_x64-setup.exe", label: "Windows setup", description: "Standard installer for personal Windows computers.", size: "2.2 MB" },
  },
} as const;
export type JCarsArtifact = keyof typeof jcarsDownload.artifacts;
export function isJCarsArtifact(value: string | null): value is JCarsArtifact { return value === "msi" || value === "exe"; }
