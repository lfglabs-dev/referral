# %% Imports
import logging
from asyncio import run

from utils.constants import (
    COMPILED_CONTRACTS,
    ETH_TOKEN_ADDRESS,
    ADMIN,
    NAMING_CONTRACT,
    MIN_CLAIM_AMOUNT,
    DEFAULT_SHARE,
)
from utils.starknet import (
    deploy_v2,
    declare_v2,
    dump_declarations,
    get_starknet_account,
    dump_deployments,
)

logging.basicConfig()
logger = logging.getLogger(__name__)
logger.setLevel(logging.INFO)


# %% Main
async def main():
    # %% Declarations
    account = await get_starknet_account()
    logger.info("ℹ️  Using account %s as deployer", hex(account.address))

    class_hash = {
        contract["contract_name"]: await declare_v2(contract["contract_name"])
        for contract in COMPILED_CONTRACTS
    }
    dump_declarations(class_hash)

    deployments = {}
    deployments["referral_Referral"] = await deploy_v2(
        "referral_Referral",
        ADMIN,
        NAMING_CONTRACT,
        ETH_TOKEN_ADDRESS,
        MIN_CLAIM_AMOUNT,
        0,
        DEFAULT_SHARE,
        0,
    )
    dump_deployments(deployments)


# %% Run
if __name__ == "__main__":
    run(main())
