use reqwest::{header, Client, Method};

pub async fn check_balance() -> eyre::Result<()> {
    let client = Client::builder().build()?;

    let mut headers = header::HeaderMap::new();
    headers.insert("Accept", "application/json".parse()?);
    headers.insert("Authorization", "Bearer <TOKEN>".parse()?);

    let request = client
        .request(Method::GET, "/api/v1/account-balances")
        .headers(headers);

    let response = request.send().await?;
    let body = response.text().await?;

    println!("{body}");

    Ok(())
}
