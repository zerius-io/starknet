#[cfg(test)]
mod tests {
use core::traits::Into;
    use starknet::get_contract_address;
    use zerius::zerius::zerius::ZeriusONFT721;
    use ZeriusONFT721::{ 
        CoreImpl, ReferralImpl, ERC721Impl, OwnableImpl, SRC5Impl
    };
    use zerius::zerius::interface::{ IZeriusONFT721CoreDispatcher, IZeriusONFT721CoreDispatcherTrait };
    use openzeppelin::tests::mocks::erc721_receiver::ERC721Receiver;
    use openzeppelin::token::erc20::interface::{ 
        IERC20DispatcherTrait, IERC20Dispatcher 
    };
    use openzeppelin::token::erc721::interface::{ 
        IERC721DispatcherTrait, IERC721Dispatcher 
    };
    use openzeppelin::token::erc20::ERC20;
    use openzeppelin::utils::serde::SerializedAppend;
    use zerius::tests::utils;
    use array::{ Array, ArrayTrait };
    use starknet::contract_address_const;
    use starknet::testing;
    use starknet::ContractAddress;
    use starknet::contract_address_try_from_felt252;
    use starknet::contract_address_to_felt252;

    const DEFAULT_REFERRAL_BIPS: u16 = 1000;
    const DEFAULT_MINT_FEE: u256 = 100;
    const TOKEN_URI: felt252 = 'hrrps://token.uri';

    const ETH_ADDRESS: felt252 = 0x049d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7;

    fn STATE() -> ZeriusONFT721::ContractState {
        ZeriusONFT721::contract_state_for_testing()
    }

    fn OWNER() -> ContractAddress {
        contract_address_const::<'OWNER'>()
    }

    fn FEE_COLLECTOR() -> ContractAddress {
        contract_address_const::<'FEE_COLLECTOR'>()
    }

    fn MALEFACTOR() -> ContractAddress {
        contract_address_const::<'MALEFACTOR'>()
    }
    
    fn MINTER() -> ContractAddress {
        utils::deploy(ERC721Receiver::TEST_CLASS_HASH, array![])
    }

    fn setup() -> ZeriusONFT721::ContractState {
        let mut state = STATE();
        let owner = OWNER();
        let fee_collector = FEE_COLLECTOR();
        let referral_earning_bips = DEFAULT_REFERRAL_BIPS;
        let mint_fee = DEFAULT_MINT_FEE;

        ZeriusONFT721::constructor(
            ref state, 
            owner, 
            fee_collector, 
            referral_earning_bips, 
            mint_fee,
        );

        return state;
    }

    fn deploy_core() -> IZeriusONFT721CoreDispatcher {
        let mut calldata = array![];

        calldata.append_serde(OWNER());
        calldata.append_serde(FEE_COLLECTOR());
        calldata.append_serde(DEFAULT_REFERRAL_BIPS);
        calldata.append_serde(DEFAULT_MINT_FEE);

        let address = utils::deploy(ZeriusONFT721::TEST_CLASS_HASH, calldata);
        IZeriusONFT721CoreDispatcher { contract_address: address }
    }

    fn deploy_erc721(address: ContractAddress) -> IERC721Dispatcher {
        IERC721Dispatcher { contract_address: address }
    }

    fn deploy_erc20(recipient: ContractAddress, initial_supply: u256) -> IERC20Dispatcher {
        let name = 0;
        let symbol = 0;
        let mut calldata = array![];

        calldata.append_serde(name);
        calldata.append_serde(symbol);
        calldata.append_serde(initial_supply);
        calldata.append_serde(recipient);

        let address = utils::deploy(ERC20::TEST_CLASS_HASH, calldata);
        IERC20Dispatcher { contract_address: address }
    }

    #[test]
    #[available_gas(2000000)]
    fn test_constructor() {
        let mut state = STATE();
        let owner = OWNER();
        let fee_collector = FEE_COLLECTOR();
        let referral_earning_bips = 1000_u16;
        let mint_fee = 100_u256;

        ZeriusONFT721::constructor(
            ref state, 
            owner, 
            fee_collector, 
            referral_earning_bips, 
            mint_fee,
        );

        let after_next_mint_id = CoreImpl::getNextMintId(@state);
        let after_fee_collector = CoreImpl::getFeeCollector(@state);
        let after_referral_earning_bips = ReferralImpl::getReferralEarningBips(@state);
        let after_mint_fee = CoreImpl::getMintFee(@state);

        assert(after_next_mint_id == ZeriusONFT721::START_MINT_ID, 'Mint id should be start mint id');
        assert(after_fee_collector == fee_collector, 'Fee collector is not set');
        assert(after_referral_earning_bips == referral_earning_bips, 'Referral bips is not set');
        assert(after_mint_fee == mint_fee, 'Mint fee is not set');
    }

    #[test]
    #[available_gas(2000000)]
    fn test_setMintFee() {
        let mut state = setup();
        let new_mint_fee = DEFAULT_MINT_FEE + 100;
        testing::set_caller_address(OWNER());

        CoreImpl::setMintFee(ref state, new_mint_fee);

        let after_mint_fee = CoreImpl::getMintFee(@state);

        assert(after_mint_fee == new_mint_fee, 'Mint fee is not set');
    }

    #[test]
    #[available_gas(2000000)]
    #[should_panic(expected: ('Caller is not the owner',))]
    fn test_setMintFee_fail_onlyOwner() {
        let mut state = setup();
        let new_mint_fee = DEFAULT_MINT_FEE + 100;
        testing::set_caller_address(MALEFACTOR());

        CoreImpl::setMintFee(ref state, new_mint_fee);
    }

    #[test]
    #[available_gas(2000000)]
    fn test_setFeeCollector() {
        let mut state = setup();
        let new_fee_collector = OWNER();
        testing::set_caller_address(OWNER());

        CoreImpl::setFeeCollector(ref state, new_fee_collector);

        let after_fee_collector = CoreImpl::getFeeCollector(@state);

        assert(after_fee_collector == new_fee_collector, 'Collector is not set');
    }

    #[test]
    #[available_gas(2000000)]
    #[should_panic(expected: ('Caller is not the owner',))]
    fn test_setFeeCollector_fail_onlyOwner() {
        let mut state = setup();
        let new_fee_collector = OWNER();
        testing::set_caller_address(MALEFACTOR());

        CoreImpl::setFeeCollector(ref state, new_fee_collector);
    }

    #[test]
    #[available_gas(9000000)]
    fn test_mint() {
        testing::set_caller_address(OWNER());

        let core_dispatcher = deploy_core();
        // let erc721_dispatcher = deploy_erc721(core_dispatcher.contract_address);
        let token_uri = TOKEN_URI;
        let minter = MINTER();

        let mint_fee = core_dispatcher.getMintFee();
        let native_token = deploy_erc20(minter, mint_fee * 2);

        // core_dispatcher.setFeeTokenAddress(contract_address_to_felt252(native_token.contract_address));

        testing::set_caller_address(minter);
        native_token.approve(core_dispatcher.contract_address, mint_fee);

        // let before_minter_balance = erc721_dispatcher.balance_of(minter);
        let before_fee_earned = core_dispatcher.getFeeEarnedAmount();
        let before_next_mint_id = core_dispatcher.getNextMintId();
        let before_contract_balance = native_token.balance_of(core_dispatcher.contract_address);

        // core_dispatcher.mint(token_uri);

        // let after_minter_balance = erc721_dispatcher.balance_of(minter);
        let after_fee_earned = core_dispatcher.getFeeEarnedAmount();
        let after_next_mint_id = core_dispatcher.getNextMintId();
        let after_contract_balance = native_token.balance_of(core_dispatcher.contract_address);

        // assert(after_minter_balance == before_minter_balance + 1, 'Minter balance should change');
        assert(after_fee_earned - before_fee_earned == mint_fee, 'Fee earned should change');
        assert(after_next_mint_id == before_next_mint_id + 1, 'Mint id should change');
        assert(after_contract_balance == before_contract_balance + mint_fee, 'Contract balance should change');
    }
}
