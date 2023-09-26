fn OWNER() -> starknet::ContractAddress {
    starknet::contract_address_const::<10>()
}

fn OTHER() -> starknet::ContractAddress {
    starknet::contract_address_const::<20>()
}

fn USER() -> starknet::ContractAddress {
    starknet::contract_address_const::<30>()
}

fn ZERO() -> starknet::ContractAddress {
    Zeroable::zero()
}

fn REFERRAL_ADDR() -> starknet::ContractAddress {
    starknet::contract_address_const::<3>()
}


fn USER_A() -> starknet::ContractAddress {
    starknet::contract_address_const::<500>()
}

fn USER_B() -> starknet::ContractAddress {
    starknet::contract_address_const::<501>()
}

fn USER_C() -> starknet::ContractAddress {
    starknet::contract_address_const::<502>()
}
