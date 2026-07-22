use std::{env,fs,path::PathBuf};
fn main(){
 tauri_build::build();
 let source=PathBuf::from(env::var("CARGO_MANIFEST_DIR").expect("manifest directory")).join("../../refs/SimConnect.dll");
 println!("cargo:rerun-if-changed={}",source.display());
 if let Ok(out_dir)=env::var("OUT_DIR"){
  let output=PathBuf::from(out_dir).ancestors().nth(3).map(|path|path.join("SimConnect.dll"));
  if let Some(destination)=output{fs::copy(&source,&destination).unwrap_or_else(|error|panic!("failed to copy SimConnect.dll to {}: {error}",destination.display()));}
 }
}
