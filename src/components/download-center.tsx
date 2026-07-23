import { Download, MonitorDown, ShieldCheck } from "lucide-react";
import { jcarsDownload } from "@/lib/crew-downloads";

export function DownloadCenter() {
  return <section className="download-center"><div className="panel-title"><div><span className="kicker">CREW SOFTWARE DISTRIBUTION</span><h2>Download Center</h2></div><span className="download-version">JCARS {jcarsDownload.version}</span></div><p className="download-intro">Approved JVA software for Windows. Links are private to authenticated crew and expire shortly after they are opened.</p><div className="download-artifacts">{Object.entries(jcarsDownload.artifacts).map(([format, artifact]) => <article key={format}><MonitorDown /><span>WINDOWS X64 · {artifact.size}</span><h3>{artifact.label}</h3><p>{artifact.description}</p><a className="button primary" href={`/api/downloads/jcars?format=${format}`}><Download size={15} /> Download JCars</a></article>)}</div><div className="download-notice"><ShieldCheck size={16} /><span>Only install JCars from this portal. Version {jcarsDownload.version} is the current approved build.</span></div></section>;
}
