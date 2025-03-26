use alloy::{
    hex,
    network::TransactionBuilder,
    providers::{Provider, ProviderBuilder},
    rpc::types::TransactionRequest,
};

use crate::Dough;

pub async fn setup() -> Result<
    Dough::DoughInstance<
        (),
        alloy::providers::fillers::FillProvider<
            alloy::providers::fillers::JoinFill<
                alloy::providers::fillers::JoinFill<
                    alloy::providers::Identity,
                    alloy::providers::fillers::JoinFill<
                        alloy::providers::fillers::GasFiller,
                        alloy::providers::fillers::JoinFill<
                            alloy::providers::fillers::BlobGasFiller,
                            alloy::providers::fillers::JoinFill<
                                alloy::providers::fillers::NonceFiller,
                                alloy::providers::fillers::ChainIdFiller,
                            >,
                        >,
                    >,
                >,
                alloy::providers::fillers::WalletFiller<alloy::network::EthereumWallet>,
            >,
            alloy::providers::layers::AnvilProvider<alloy::providers::RootProvider>,
        >,
    >,
    eyre::Error,
> {
    // Spin up local Anvil node.
    let provider = ProviderBuilder::new().on_anvil_with_wallet();

    let bytecode = hex::decode(
        std::fs::read_to_string("../src/bytecode/Dough.bin").expect(
            "Well... go make that bytecode.\nsolc Dough.flat.sol --via-ir --optimize --bin -o bytecode\n",
        ),
    )?;
    let tx = TransactionRequest::default().with_deploy_code(bytecode);

    let receipt = provider.send_transaction(tx).await?.get_receipt().await?;
    println!("{:?}", receipt.transaction_hash);

    let contract_adr = receipt
        .contract_address
        .expect("Failed to get contract address ig");
    println!("{contract_adr}");

    let contract = Dough::new(contract_adr, provider.clone());

    println!("Deployed contract at address: {}", contract_adr);
    std::fs::write("./addr", contract.address().to_string())
        .expect("Should have written the contract address");

    Ok(contract)
}
