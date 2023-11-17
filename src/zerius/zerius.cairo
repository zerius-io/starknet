#[starknet::contract]
mod ZeriusONFT721 {
    use array::SpanTrait;
    use array::ArrayTrait;
    use option::OptionTrait;
    use starknet::ContractAddress;
    use starknet::{
        get_caller_address, get_contract_address, contract_address_try_from_felt252,
    };
    use traits::Into;
    use zeroable::Zeroable;

    use openzeppelin::token::erc20::interface::{ 
        IERC20CamelDispatcherTrait, IERC20CamelDispatcher,
    };
    use openzeppelin::access::ownable::Ownable;
    use openzeppelin::access::ownable::interface::{
        IOwnable, IOwnableCamelOnly,
    };
    use openzeppelin::token::erc721::ERC721;
    use openzeppelin::token::erc721::interface::{
        IERC721, IERC721CamelOnly,
    };
    use openzeppelin::introspection::src5::SRC5;
    use openzeppelin::introspection::interface::{ 
        ISRC5, ISRC5Camel,
    };

    use zerius::zerius::interface::{
        IZeriusONFT721Core, IZeriusONFT721Referral, IZeriusONFT721_CORE_ID, IZeriusONFT721_REFERRAL_ID,
    };

    //////////////////////////////
    //        Constants         //
    //////////////////////////////

    const ONE_HUNDRED_PERCENT: u16 = 10000; // 100%
    const FIFTY_PERCENT: u16 = 5000; // 50%
    const DENOMINATOR: u16 = 10000;

    const START_MINT_ID: u32 = 15000001;
    const MAX_MINT_ID: u32 = 20000000;

    const ETH_ADDRESS: felt252 = 0x049d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7;

    //////////////////////////////
    //          Errors          //
    //////////////////////////////

    mod Errors {
        const INVALID_FEE_COLLECTOR: felt252 = 'Invalid fee collector address';
        const INVALID_TOKEN: felt252 = 'Invalid token address';
        const NOTHING_TO_CLAIM: felt252 = 'Nothing to claim';
        const INVALID_REFERRER: felt252 = 'Invalid referrer address';
        const INVALID_REFERRAL_BIPS: felt252 = 'Referral bips too high';
        const CALLER_NOT_FEE_COLLECTOR: felt252 = 'Caller is not fee collector';
        const INCORRECT_ALLOWANCE: felt252 = 'Mint fee exceeds allowance';
        const MINT_LIMIT_EXCEEDED: felt252 = 'Mint exceeds limit';
    }

    //////////////////////////////
    //          Events          //
    //////////////////////////////

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        MintFeeChanged: MintFeeChanged,
        ReferralEarningBipsChanged: ReferralEarningBipsChanged,
        EarningBipsForReferrerChanged: EarningBipsForReferrerChanged, 
        FeeCollectorChanged: FeeCollectorChanged,
        FeeTokenChanged: FeeTokenChanged,
        ONFTMinted: ONFTMinted,
        FeeEarningsClaimed: FeeEarningsClaimed,
        ReferrerEarningsClaimed: ReferrerEarningsClaimed,
    }

    #[derive(Drop, starknet::Event)]
    struct MintFeeChanged {
        #[key]
        old_mint_fee: u256,
        #[key]
        new_mint_fee: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct ReferralEarningBipsChanged {
        #[key]
        old_bips: u16,
        #[key]
        new_bips: u16,
    }

    #[derive(Drop, starknet::Event)]
    struct EarningBipsForReferrerChanged {
        #[key]
        referrer: ContractAddress,
        old_bips: u16,
        new_bips: u16,
    }

    #[derive(Drop, starknet::Event)]
    struct FeeCollectorChanged {
        #[key]
        old_collector: ContractAddress,
        #[key]
        new_collector: ContractAddress,
    }

     #[derive(Drop, starknet::Event)]
    struct FeeTokenChanged {
        #[key]
        old_token: ContractAddress,
        #[key]
        new_token: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    struct ONFTMinted {
        #[key]
        minter: ContractAddress,
        #[key]
        item_id: u32,
        fee_earnings: u256,
        #[key]
        referrer: ContractAddress,
        referrer_earnings: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct FeeEarningsClaimed {
        #[key]
        collector: ContractAddress,
        claimed_amount: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct ReferrerEarningsClaimed {
        #[key]
        referrer: ContractAddress,
        claimed_amount: u256,
    }

    //////////////////////////////
    //         Storage          //
    //////////////////////////////

    #[storage]
    struct Storage {
        // Core
        next_mint_id: u32,
        mint_fee: u256,
        fee_collector: ContractAddress,
        fee_earned_amount: u256,
        fee_claimed_amount: u256,

        // Referral
        referral_earning_bips_common: u16,
        referrers_earning_bips: LegacyMap<ContractAddress, u16>,
        referred_transactions_count: LegacyMap<ContractAddress, u32>,
        referrers_earned_amount: LegacyMap<ContractAddress, u256>,
        referrers_claimed_amount: LegacyMap<ContractAddress, u256>,
    }

    //////////////////////////////
    //        Constructor       //
    //////////////////////////////

    #[constructor]
    fn constructor(
        ref self: ContractState,
        owner: ContractAddress,
        fee_collector: ContractAddress,
        referral_earning_bips: u16,
        mint_fee: u256,
    ) {
        let name = 'ZeriusONFT Minis';
        let symbol = 'ZRSM';
        let mut erc721_unsafe_state = self._get_erc721_unsafe_state();
        ERC721::InternalImpl::initializer(ref erc721_unsafe_state, name, symbol);

        let mut ownable_unsafe_state = self._get_ownable_unsafe_state();
        Ownable::InternalImpl::initializer(ref ownable_unsafe_state, owner);

        let mut src5_unsafe_state = SRC5::unsafe_new_contract_state();
        SRC5::InternalImpl::register_interface(ref src5_unsafe_state, IZeriusONFT721_CORE_ID);
        SRC5::InternalImpl::register_interface(ref src5_unsafe_state, IZeriusONFT721_REFERRAL_ID);
        
        self.next_mint_id.write(START_MINT_ID);
        self.fee_collector.write(fee_collector);
        self.referral_earning_bips_common.write(referral_earning_bips);
        self.mint_fee.write(mint_fee);
    }

    //////////////////////////////
    //    External functions    //
    //////////////////////////////

    //
    // Core
    //
    #[external(v0)]
    impl CoreImpl of IZeriusONFT721Core<ContractState> {
        
        //
        // Setters / getters
        //

        fn setMintFee(ref self: ContractState, mint_fee: u256) {
            AccessControlImpl::only_owner(@self);

            let old_mint_fee = self.mint_fee.read();
            self.mint_fee.write(mint_fee);
            
            self.emit(MintFeeChanged { old_mint_fee: old_mint_fee, new_mint_fee: mint_fee });
        }

        fn setFeeCollector(ref self: ContractState, fee_collector: ContractAddress) {
            AccessControlImpl::only_owner(@self);
            assert(fee_collector.is_non_zero(), Errors::INVALID_FEE_COLLECTOR);

            let old_collector = self.fee_collector.read();
            self.fee_collector.write(fee_collector);

            self.emit(FeeCollectorChanged { old_collector: old_collector, new_collector: fee_collector });
        }

        fn getNextMintId(self: @ContractState) -> u32 {
            self.next_mint_id.read()
        }

        fn getFeeEarnedAmount(self: @ContractState) -> u256 {
            self.fee_earned_amount.read()
        }
        
        fn getFeeClaimedAmount(self: @ContractState) -> u256 {
            self.fee_claimed_amount.read()
        }

        fn getMintFee(self: @ContractState) -> u256 {
            self.mint_fee.read()
        }

        fn getFeeCollector(self: @ContractState) -> ContractAddress {
            self.fee_collector.read()
        }

        //
        // Logic
        //

        fn mint(ref self: ContractState, uri: felt252) {
            let minter = get_caller_address();
            let fee_earned = self._charge_mint_fee(minter);
            let new_token_id = self._mint(minter, uri);

            self.emit(ONFTMinted {
                minter: minter, 
                item_id: new_token_id, 
                fee_earnings: fee_earned, 
                referrer: Zeroable::zero(), 
                referrer_earnings: 0,
            })
        }

        fn claimFeeEarnings(ref self: ContractState) {
            AccessControlImpl::only_fee_collector(@self);

            let fee_earned_amount = self.fee_earned_amount.read();
            assert(fee_earned_amount > 0, Errors::NOTHING_TO_CLAIM);

            self.fee_earned_amount.write(0);
            self.fee_claimed_amount.write(self.fee_claimed_amount.read() + fee_earned_amount);

            let fee_collector = self.fee_collector.read();
            self._send_eth_to(fee_collector, fee_earned_amount);

            self.emit(FeeEarningsClaimed { collector: fee_collector, claimed_amount: fee_earned_amount });
        }
    }

    //
    // Referral
    //
    #[external(v0)]
    impl ReferralImpl of IZeriusONFT721Referral<ContractState> {

        //
        // Setters / getters
        //

        fn setReferralEarningBips(ref self: ContractState, earning_bips: u16) {
            AccessControlImpl::only_owner(@self);
            assert(earning_bips <= FIFTY_PERCENT, Errors::INVALID_REFERRAL_BIPS);

            let old_bips = self.referral_earning_bips_common.read();
            self.referral_earning_bips_common.write(earning_bips);

            self.emit(ReferralEarningBipsChanged { old_bips: old_bips, new_bips: earning_bips });
        }
        
        fn setEarningBipsForReferrer(ref self: ContractState, referrer: ContractAddress, earning_bips: u16) {
            AccessControlImpl::only_owner(@self);
            assert(referrer.is_non_zero(), Errors::INVALID_REFERRER);
            assert(earning_bips <= ONE_HUNDRED_PERCENT, Errors::INVALID_REFERRAL_BIPS);

            let old_bips = self.referrers_earning_bips.read(referrer);
            self.referrers_earning_bips.write(referrer, earning_bips);

            self.emit(EarningBipsForReferrerChanged { referrer: referrer, old_bips: old_bips, new_bips: earning_bips})
        }

        fn getReferredTransactionsCount(self: @ContractState, referrer: ContractAddress) -> u32 {
            self.referred_transactions_count.read(referrer)
        }
        
        fn getReferrerEarnedAmount(self: @ContractState, referrer: ContractAddress) -> u256 {
            self.referrers_earned_amount.read(referrer)
        }
        
        fn getReferrerClaimedAmount(self: @ContractState, referrer: ContractAddress) -> u256 {
            self.referrers_claimed_amount.read(referrer)
        }

        fn getReferralEarningBips(self: @ContractState) -> u16 {
            self.referral_earning_bips_common.read()
        }

        fn getEarningBipsForReferrer(self: @ContractState, referrer: ContractAddress) -> u16 {
            self.referrers_earning_bips.read(referrer)
        }

        //
        // Logic
        //

        fn mintWithReferrer(ref self: ContractState, uri: felt252, referrer: ContractAddress) {
            let minter = get_caller_address();
            self.referred_transactions_count.write(referrer, self.referred_transactions_count.read(referrer) + 1);

            let referrer_earnings = self._charge_mint_fee_with_referrer(minter: minter, referrer: referrer);
            let fee_earnings = self.mint_fee.read() - referrer_earnings;
            let new_token_id = self._mint(minter, uri);

            self.emit(ONFTMinted {
                minter: minter,
                item_id: new_token_id, 
                fee_earnings: fee_earnings, 
                referrer: referrer, 
                referrer_earnings: referrer_earnings,
            })
        }

        fn claimReferralEarnings(ref self: ContractState) {
            let referrer = get_caller_address();
            let fee_earned_amount = self.referrers_earned_amount.read(referrer);
            assert(fee_earned_amount > 0, Errors::NOTHING_TO_CLAIM);

            self.referrers_earned_amount.write(referrer, 0);
            self.referrers_claimed_amount.write(referrer, self.referrers_claimed_amount.read(referrer) + fee_earned_amount);

            self._send_eth_to(referrer, fee_earned_amount);

            self.emit(ReferrerEarningsClaimed { referrer: referrer, claimed_amount: fee_earned_amount });
        }
    }

    //////////////////////////////
    //    Internal functions    //
    //////////////////////////////

    //
    // Access helpers
    //
    #[generate_trait]
    impl AccessControlImpl of AccessControlTrait {

        #[inline(always)]
        fn only_owner(self: @ContractState) {
            let unsafe_state = Ownable::unsafe_new_contract_state();
            Ownable::InternalImpl::assert_only_owner(@unsafe_state);
        }

        #[inline(always)]
        fn only_fee_collector(self: @ContractState) {
            let caller = get_caller_address();
            assert(self.fee_collector.read() == caller, Errors::CALLER_NOT_FEE_COLLECTOR);
        }
    }

    //
    // Internal
    //
    #[generate_trait]
    impl InternalImpl of InternalTrait {

        fn _get_erc721_unsafe_state(self: @ContractState) -> ERC721::ContractState {
            ERC721::unsafe_new_contract_state()
        }

        fn _get_ownable_unsafe_state(self: @ContractState) -> Ownable::ContractState {
            Ownable::unsafe_new_contract_state()
        }

        fn _fee_token_contract(self: @ContractState) -> ContractAddress {
            contract_address_try_from_felt252(ETH_ADDRESS).unwrap()
        }

        fn _get_eth_allowance(self: @ContractState, sender: ContractAddress) -> u256 {
            let fee_token_contract = self._fee_token_contract();
            let this_contract = get_contract_address();
            return IERC20CamelDispatcher { contract_address: fee_token_contract }.allowance(sender, this_contract);
        }

        fn _add_earned_amount(ref self: ContractState, amount: u256) {
            self.fee_earned_amount.write(self.fee_earned_amount.read() + amount);
        }

        fn _charge_mint_fee(ref self: ContractState, minter: ContractAddress) -> u256 {
            let allowance = self._get_eth_allowance(minter);
            let mint_fee = self.mint_fee.read();
            assert(allowance >= mint_fee, Errors::INCORRECT_ALLOWANCE);

            let fee_token_contract = self._fee_token_contract();
            let this_contract = get_contract_address();
            IERC20CamelDispatcher { contract_address: fee_token_contract }.transferFrom(minter, this_contract, mint_fee);

            self._add_earned_amount(mint_fee);

            return mint_fee;
        }

        fn _estimate_referrer_earnings(self: @ContractState, referrer: ContractAddress, fee: u256) -> u256 {
            let referrer_custom_bips = self.referrers_earning_bips.read(referrer);
            let referrer_bips = if referrer_custom_bips == 0 {
                self.referral_earning_bips_common.read()
            } else {
                referrer_custom_bips
            }.into();

            return (fee * referrer_bips) / DENOMINATOR.into();
        }

        fn _charge_mint_fee_with_referrer(
            ref self: ContractState, 
            minter: ContractAddress, 
            referrer: ContractAddress,
        ) -> u256 {
            let allowance = self._get_eth_allowance(minter);
            let mint_fee = self.mint_fee.read();
            assert(allowance >= mint_fee, Errors::INCORRECT_ALLOWANCE);

            let referrer_earnings = self._estimate_referrer_earnings(referrer, mint_fee);
            let fee_earnings = mint_fee - referrer_earnings;
            self.referrers_earned_amount.write(referrer, self.referrers_earned_amount.read(referrer) + referrer_earnings);
            self._add_earned_amount(mint_fee);

            let fee_token_contract = self._fee_token_contract();
            let this_contract = get_contract_address();
            IERC20CamelDispatcher { contract_address: fee_token_contract }.transferFrom(minter, this_contract, mint_fee);

            return referrer_earnings;
        }

        fn _mint(ref self: ContractState, minter: ContractAddress, uri: felt252) -> u32 {
            let next_token_id = self.next_mint_id.read();
            assert(next_token_id <= MAX_MINT_ID, Errors::MINT_LIMIT_EXCEEDED);

            self.next_mint_id.write(next_token_id + 1);

            let token_id: u256 = next_token_id.into();
            let mut unsafe_state = ERC721::unsafe_new_contract_state();
            ERC721::InternalImpl::_safe_mint(ref unsafe_state, minter, token_id, ArrayTrait::new().span());
            ERC721::InternalImpl::_set_token_uri(ref unsafe_state, token_id, uri);

            return next_token_id;
        }

        fn _send_eth_to(self: @ContractState, to: ContractAddress, amount: u256) {
            let fee_token_contract = self._fee_token_contract();
            let this_contract = get_contract_address();
            IERC20CamelDispatcher { contract_address: fee_token_contract }.transfer(to, amount);
        }
    }

    //////////////////////////////
    //        Overrides         //
    //////////////////////////////

    //
    // ERC721 Implementation
    //
    #[external(v0)]
    impl ERC721Impl of IERC721<ContractState> {

        fn balance_of(self: @ContractState, account: ContractAddress) -> u256 {
            ERC721::ERC721Impl::balance_of(@self._get_erc721_unsafe_state(), account)
        }

        fn owner_of(self: @ContractState, token_id: u256) -> ContractAddress {
            ERC721::ERC721Impl::owner_of(@self._get_erc721_unsafe_state(), token_id)
        }

        fn transfer_from(ref self: ContractState, from: ContractAddress, to: ContractAddress, token_id: u256) {
            let mut unsafe_state = self._get_erc721_unsafe_state();
            ERC721::ERC721Impl::transfer_from(ref unsafe_state, from, to, token_id);
        }

        fn safe_transfer_from(
            ref self: ContractState,
            from: ContractAddress,
            to: ContractAddress,
            token_id: u256,
            data: Span<felt252>,
        ) {
            let mut unsafe_state = self._get_erc721_unsafe_state();
            ERC721::ERC721Impl::safe_transfer_from(
                ref unsafe_state,
                from,
                to,
                token_id,
                data,
            );
        }

        fn approve(ref self: ContractState, to: ContractAddress, token_id: u256) {
            let mut unsafe_state = self._get_erc721_unsafe_state();
            ERC721::ERC721Impl::approve(ref unsafe_state, to, token_id);
        }

        fn set_approval_for_all(ref self: ContractState, operator: ContractAddress, approved: bool) {
            let mut unsafe_state = self._get_erc721_unsafe_state();
            ERC721::ERC721Impl::set_approval_for_all(ref unsafe_state, operator, approved);
        }

        fn get_approved(self: @ContractState, token_id: u256) -> ContractAddress {
            ERC721::ERC721Impl::get_approved(@self._get_erc721_unsafe_state(), token_id)
        }

        fn is_approved_for_all(
            self: @ContractState, owner: ContractAddress, operator: ContractAddress
        ) -> bool {
            ERC721::ERC721Impl::is_approved_for_all(@self._get_erc721_unsafe_state(), owner, operator)
        }
    }

    //
    // ERC721 camel only Implementation
    //
    #[external(v0)]
    impl ERC721CamelOnlyImpl of IERC721CamelOnly<ContractState> {

        fn balanceOf(self: @ContractState, account: ContractAddress) -> u256 {
            self.balance_of(account)
        }

        fn ownerOf(self: @ContractState, tokenId: u256) -> ContractAddress {
            self.owner_of(tokenId)
        }

        fn transferFrom(ref self: ContractState, from: ContractAddress, to: ContractAddress, tokenId: u256) {
            self.transferFrom(from, to, tokenId);
        }

        fn safeTransferFrom(
            ref self: ContractState,
            from: ContractAddress,
            to: ContractAddress,
            tokenId: u256,
            data: Span<felt252>,
        ) {
            self.safe_transfer_from(from, to, tokenId, data);
        }

        fn setApprovalForAll(ref self: ContractState, operator: ContractAddress, approved: bool) {
            self.set_approval_for_all(operator, approved);
        }

        fn getApproved(self: @ContractState, tokenId: u256) -> ContractAddress {
            self.get_approved(tokenId)
        }

        fn isApprovedForAll(
            self: @ContractState, owner: ContractAddress, operator: ContractAddress
        ) -> bool {
            self.is_approved_for_all(owner, operator)
        }
    }

    //
    // SRC5 Implementation
    //
    #[external(v0)]
    impl SRC5Impl of ISRC5<ContractState> {
        fn supports_interface(self: @ContractState, interface_id: felt252) -> bool {
            return if interface_id == IZeriusONFT721_CORE_ID
                || interface_id == IZeriusONFT721_REFERRAL_ID 
            {
                true
            } else {
                ERC721::SRC5Impl::supports_interface(@self._get_erc721_unsafe_state(), interface_id)
            };
        }
    }

    //
    // SRC5 camel Implementation
    //
    #[external(v0)]
    impl SRC5CamelImpl of ISRC5Camel<ContractState> {
        fn supportsInterface(self: @ContractState, interfaceId: felt252) -> bool {
            return self.supports_interface(interfaceId);
        }
    }

    //
    // Ownable Implementation
    //
    #[external(v0)]
    impl OwnableImpl of IOwnable<ContractState> {

        fn owner(self: @ContractState) -> ContractAddress {
            Ownable::OwnableImpl::owner(@self._get_ownable_unsafe_state())
        }

        fn transfer_ownership(ref self: ContractState, new_owner: ContractAddress) {
            let mut unsafe_state = self._get_ownable_unsafe_state();
            Ownable::OwnableImpl::transfer_ownership(ref unsafe_state, new_owner);
        }

        fn renounce_ownership(ref self: ContractState) {
            let mut unsafe_state = self._get_ownable_unsafe_state();
            Ownable::OwnableImpl::renounce_ownership(ref unsafe_state);
        }
    }

    //
    // Ownable camel only Implementation
    //
    #[external(v0)]
    impl OwnableCamelOnlyImpl of IOwnableCamelOnly<ContractState> {

        fn transferOwnership(ref self: ContractState, newOwner: ContractAddress) {
            self.transfer_ownership(newOwner);
        }

        fn renounceOwnership(ref self: ContractState) {
            self.renounce_ownership();
        }
    }
}
