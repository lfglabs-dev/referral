# %% Imports
import logging
from asyncio import run

from utils.constants import COMPILED_CONTRACTS, ETH_TOKEN_ADDRESS
from utils.starknet import (
    declare_v2,
    deploy_v2,
    dump_declarations,
    dump_deployments,
    get_declarations,
    get_starknet_account,
    invoke,
    get_eth_contract,
    int_to_uint256,
)

logging.basicConfig()
logger = logging.getLogger(__name__)
logger.setLevel(logging.INFO)


# %% Main
async def main():
    # %% Declarations
    account = await get_starknet_account()
    logger.info(f"ℹ️  Using account {hex(account.address)} as deployer")

    class_hash = {
        contract["contract_name"]: await declare_v2(contract["contract_name"])
        for contract in COMPILED_CONTRACTS
    }
    dump_declarations(class_hash)

    # %% Deployments
    class_hash = get_declarations()

    print('class_hash', class_hash)

    
    deployments = {}
    deployments["referral_Naming"] = await deploy_v2("referral_Naming")
    deployments["referral_Referral"] = await deploy_v2(
        "referral_Referral", 
        account.address, 
        deployments["referral_Naming"]["address"],
        ETH_TOKEN_ADDRESS,
        int_to_uint256(1),
        int_to_uint256(5),
    )
    dump_deployments(deployments)

    logger.info("⏳ Configuring Contracts...")
    await invoke(
        "referral_Naming",
        "set_referral_addr",
        [int(deployments["referral_Referral"]["address"])],
    )

    # Send eth to referral contract
    logger.info("⏳ Sending ETH to Referral contract...")
    eth_contract = await get_eth_contract()

    set_allowance = eth_contract.functions["approve"].prepare(
        spender=account.address, 
        amount=int_to_uint256(10000000000000000), 
        max_fee=int(1e17)
    )
    transfer_from = eth_contract.functions["transferFrom"].prepare(
        sender=account.address, 
        recipient=deployments["referral_Referral"]["address"], 
        amount=int_to_uint256(10000000000000000), 
        max_fee=int(1e17)
    )
    response = await account.execute(calls=[set_allowance, transfer_from], max_fee=int(1e17))
    await account.client.wait_for_tx(response.transaction_hash)

    balance = (await eth_contract.functions["balanceOf"].call(deployments["referral_Referral"]["address"])).balance
    logger.info(f"✅  Transfer Complete to Referral contract with balance {balance}")

    logger.info("✅ Configuration Complete")

    logger.info("⏳ Generating dummy data on the devnet...")
    logger.info("⏳ Buying 10 domains for account...")
    for x in range(1, 10):
        await invoke(
            "referral_Naming",
            "buy_domain",
            [390000000000000180, 0, account.address]
        )

    logger.info("⏳ Claiming commissions...")
    await invoke(
            "referral_Referral",
            "claim",
            [100000, 0]
        )
    logger.info("✅ Generation Complete")


# %% Run
if __name__ == "__main__":
    run(main())