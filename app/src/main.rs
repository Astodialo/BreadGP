mod check_balance;

use std::time::Duration;

use alloy::{
    hex,
    network::TransactionBuilder,
    primitives::Uint,
    providers::{Provider, ProviderBuilder},
    rpc::types::TransactionRequest,
    sol,
};
use check_balance::check_balance;

sol!(
    #[sol(rpc)]
    Dough,
    "../src/abi/Dough.abi"
);

#[tokio::main]
async fn main() -> eyre::Result<()> {
    // Spin up local Anvil node.
    let provider = ProviderBuilder::new().on_anvil_with_wallet();

    let bytecode = hex::decode(
        std::fs::read_to_string("../src/abi/Dough.bin").expect(
            "Well... go make that bytecode.\nsolc Dough.flat.sol --via-ir --optimize --bin -o bytecode\n",
        ),
    )?;
    let tx = TransactionRequest::default().with_deploy_code(bytecode);

    println!("{:?}", tx);

    let receipt = provider.send_transaction(tx).await?.get_receipt().await?;
    println!("{:?}", receipt.transaction_hash);

    let contract_adr = receipt
        .contract_address
        .expect("Failed to get contract address ig");
    println!("{contract_adr}");

    let contract = Dough::new(contract_adr, provider.clone());

    println!("Deployed contract at address: {}", contract_adr);

    let register = contract.register(Uint::from(10), Uint::from(10));
    let tx_hash = register.send().await?.watch().await?;

    println!("Register: {tx_hash}");

    Ok(())

    //loop {
    //    let balance = check_balance().await?;
    //    std::thread::sleep(Duration::from_secs(60));

    //    if balance < 100 {
    //        let swap = contract.swapBreadToEure();
    //        let tx_hash = swap.send().await?.watch().await?;
    //    }
    //}
}
