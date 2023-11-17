use starknet::ContractAddress;

const IZeriusONFT721_CORE_ID: felt252 = 0x3fbd28840810bd7685ffa8f36ad2fb454b92aec5fc61072de333afd05b97a8e;
const IZeriusONFT721_REFERRAL_ID: felt252 = 0x1e044c88144b8c2762ef4e7ad0ba14f45c2217eea4a988f46c2ba997833dd5;

#[starknet::interface]
trait IZeriusONFT721Core<TContractState> {
    //
    // Setters / getters
    //
    fn setMintFee(ref self: TContractState, mint_fee: u256);
    fn setFeeCollector(ref self: TContractState, fee_collector: ContractAddress);

    fn getNextMintId(self: @TContractState) -> u32;
    fn getFeeEarnedAmount(self: @TContractState) -> u256;
    fn getFeeClaimedAmount(self: @TContractState) -> u256;
    fn getMintFee(self: @TContractState) -> u256;
    fn getFeeCollector(self: @TContractState) -> ContractAddress;

    //
    // Logic
    //
    fn mint(ref self: TContractState, uri: felt252);
    fn claimFeeEarnings(ref self: TContractState);
}


//
// Referral
//
#[starknet::interface]
trait IZeriusONFT721Referral<TContractState> {

    //
    // Setters / getters
    //
    fn setReferralEarningBips(ref self: TContractState, earning_bips: u16);
    fn setEarningBipsForReferrer(ref self: TContractState, referrer: ContractAddress, earning_bips: u16);

    fn getReferredTransactionsCount(self: @TContractState, referrer: ContractAddress) -> u32;
    fn getReferrerEarnedAmount(self: @TContractState, referrer: ContractAddress) -> u256;
    fn getReferrerClaimedAmount(self: @TContractState, referrer: ContractAddress) -> u256;
    fn getReferralEarningBips(self: @TContractState) -> u16;
    fn getEarningBipsForReferrer(self: @TContractState, referrer: ContractAddress) -> u16;

    //
    // Logic
    //
    fn mintWithReferrer(ref self: TContractState, uri: felt252, referrer: ContractAddress);
    fn claimReferralEarnings(ref self: TContractState);
}
