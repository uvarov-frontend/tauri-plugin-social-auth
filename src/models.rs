#[derive(Debug, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SocialAccessTokenPayload {
    pub access_token: String,
}

#[derive(Debug, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SocialIdTokenPayload {
    pub id_token: String,
}

#[derive(Debug, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AppleSignInPayload {
    pub id_token: String,
    pub user_identifier: String,
    pub authorization_code: Option<String>,
    pub email: Option<String>,
    pub given_name: Option<String>,
    pub family_name: Option<String>,
}
