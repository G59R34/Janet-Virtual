use crate::models::*;
use anyhow::{Context, Result, anyhow};
use reqwest::blocking::Client;
use serde::de::DeserializeOwned;
use serde_json::{Value, json};
#[derive(Clone)]
pub struct Api {
    http: Client,
    pub base: String,
    supabase: String,
    key: String,
}
impl Api {
    pub fn new() -> Self {
        Self {
            http: Client::new(),
            base: std::env::var("JSCOPE_API_URL")
                .unwrap_or_else(|_| "http://localhost:3000".into()),
            supabase: std::env::var("JSCOPE_SUPABASE_URL")
                .unwrap_or_else(|_| "https://eecspckiiobzaxnfhyzr.supabase.co".into()),
            key: std::env::var("JSCOPE_SUPABASE_KEY")
                .unwrap_or_else(|_| "sb_publishable_HIla-nDNKc0Y-x-f3O0GAQ_Zw24rzWf".into()),
        }
    }
    fn decode<T: DeserializeOwned>(response: reqwest::blocking::Response) -> Result<T> {
        let status = response.status();
        let text = response.text()?;
        if !status.is_success() {
            let value: Value = serde_json::from_str(&text).unwrap_or_default();
            return Err(anyhow!(
                value
                    .get("error")
                    .or_else(|| value.get("message"))
                    .and_then(Value::as_str)
                    .unwrap_or(&text)
                    .to_string()
            ));
        }
        serde_json::from_str(&text).context("Invalid server response")
    }
    pub fn login(&self, email: &str, password: &str) -> Result<AuthSession> {
        #[derive(serde::Deserialize)]
        struct Login {
            access_token: String,
            refresh_token: String,
            expires_in: i64,
        }
        let r = self
            .http
            .post(format!(
                "{}/auth/v1/token?grant_type=password",
                self.supabase
            ))
            .header("apikey", &self.key)
            .json(&json!({"email":email,"password":password}))
            .send()?;
        let v: Login = Self::decode(r)?;
        Ok(AuthSession {
            access_token: v.access_token,
            refresh_token: v.refresh_token,
            expires_at: chrono::Utc::now().timestamp() + v.expires_in,
        })
    }
    fn request<T: DeserializeOwned>(
        &self,
        auth: &AuthSession,
        path: &str,
        body: Option<Value>,
        token: Option<&str>,
    ) -> Result<T> {
        let mut r = if body.is_some() {
            self.http.post(format!("{}{}", self.base, path))
        } else {
            self.http.get(format!("{}{}", self.base, path))
        }
        .bearer_auth(&auth.access_token);
        if let Some(t) = token {
            r = r.header("x-jscope-session", t)
        }
        if let Some(v) = body {
            r = r.json(&v)
        }
        Self::decode(r.send()?)
    }
    pub fn open(&self, a: &AuthSession) -> Result<ControllerSession> {
        self.request(
            a,
            "/api/jscope/session",
            Some(json!({"clientVersion":"0.2.0-native"})),
            None,
        )
    }
    pub fn claim(&self, a: &AuthSession, c: &ControllerSession, position: &str) -> Result<String> {
        let v: Value = self.request(
            a,
            "/api/jscope/position",
            Some(json!({"positionId":position,"safetyAccepted":true})),
            Some(&c.token),
        )?;
        v.get("positionSessionId")
            .and_then(Value::as_str)
            .map(str::to_owned)
            .ok_or_else(|| anyhow!("Position session missing"))
    }
    pub fn snapshot(&self, a: &AuthSession, c: &ControllerSession) -> Result<Snapshot> {
        self.request(a, "/api/jscope/snapshot", None, Some(&c.token))
    }
    pub fn instruction(
        &self,
        a: &AuthSession,
        c: &ControllerSession,
        position_session: &str,
        aircraft: &str,
        kind: &str,
        text: &str,
        parameters: Value,
    ) -> Result<Value> {
        self.request(a,"/api/jscope/instructions",Some(json!({"positionSessionId":position_session,"aircraftSessionId":aircraft,"type":kind,"parameters":parameters,"text":text,"nonce":uuid::Uuid::new_v4().to_string()})),Some(&c.token))
    }
}
