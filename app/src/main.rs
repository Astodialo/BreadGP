mod check_balance;
mod setup;

use std::time::Duration;

use alloy::{primitives::Uint, sol};
use check_balance::check_balance;
use setup::setup;

sol!(
    #[sol(rpc)]
    "../src/Dough.flat.sol"
);

#[tokio::main]
async fn main() -> eyre::Result<()> {
    let contract = setup().await?;

    let register = contract.register(Uint::from(10), Uint::from(10));
    let tx_hash = register.send().await?.watch().await?;

    println!("Register: {tx_hash}");

    loop {
        let balance = check_balance().await?;
        std::thread::sleep(Duration::from_secs(60));

        if balance < 100 {
            let swap = contract.swapBreadToEure(payload);
            let tx_hash = swap.send().await?.watch().await?;
        }
    }
}
