fn OWNER() -> starknet::ContractAddress {
    starknet::contract_address_const::<0x123>()
}

fn OTHER() -> starknet::ContractAddress {
    starknet::contract_address_const::<0x456>()
}

fn USER() -> starknet::ContractAddress {
    starknet::contract_address_const::<30>()
}

fn ZERO() -> starknet::ContractAddress {
    Zeroable::zero()
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
