contract;

use std::address::Address;
use std::hash::*;
use std::auth::{AuthError, Sender, msg_sender};
use std::token::transfer_to_output;

abi MyContract {
    fn start_auction(beneficiary: Address, biddingEnd: u64, revealEnd: u64);
    fn bid(blindedBid: b256);
    fn reveal(values: [u64], fakes: [bool], secrets: [b256]);
}

const ETH = ~ContractId::from(0x0000000000000000000000000000000000000000000000000000000000000000);

storage {
    beneficiary: Address,
    biddingEnd: u64,
    revealEnd: u64,
    ended: bool,

    highestBidder: Address,
    highestBid: u64,
}

const BIDS: b256 = 0x0000000000000000000000000000000000000000000000000000000000000000;
const BIDNOS: b256 = 0x0000000000000000000000000000000000000000000000000000000000000001;

fn addBid(addy: Address, bid: Bid) {
    let index_slot = hash_pair(BIDNOS, addy, HashMethod::Sha256);
    let index = get::<u64>(index_slot);
    store(index_slot, index + 1);
    let storage_slot = hash_pair(BIDS, sha256(addy, index), HashMethod::Sha256);

    store(storage_slot, bid);
}

//for setting a specific bid index instead of adding a new one ontop
fn setBid(addy: Address, bid: Bid, index: u64) {
    let storage_slot = hash_pair(BIDS, sha256(addy, index), HashMethod::Sha256);

    store(storage_slot, bid);
}

fn getBid(addy: Address, index: u64) -> Bid {
    let storage_slot = hash_pair(BIDS, sha256(addy, index), HashMethod::Sha256);
    get::<Bid>(storage_slot)
}

fn getAmountOfBids(addy: Address) -> u64 {
    let index_slot = hash_pair(BIDNOS, addy, HashMethod::Sha256);
    get::<u64>(index_slot)
}

const PENDINGRETURNS: b256 = 0x0000000000000000000000000000000000000000000000000000000000000002;

fn addPendingReturn(addy: Address, amount: u64) {
    let storage_slot = hash_pair(PENDINGRETURNS, addy, HashMethod::Sha256);
    store(storage_slot, amount);
}

fn getPendingReturns(addy: Address) -> u64 {
    let storage_slot = hash_pair(PENDINGRETURNS, addy, HashMethod::Sha256);
    get::<u64>(storage_slot)
}

impl MyContract for Contract {
    fn start_auction(beneficiary: Address, biddingEnd: u64, revealEnd: u64) {
        require(storage.ended);
        storage.ended = false;
        storage.beneficiary = beneficiary;
        storage.biddingEnd = biddingEnd;
        storage.revealEnd = revealEnd;

        storage.highestBidder =  ~Address::from(0x0000000000000000000000000000000000000000000000000000000000000000);
        storage.highestBid = 0;
    }

    fn bid(blindedBid: b256) {
        require(!storage.ended);
        require(storage.biddingEnd > block.timestamp);

        bid = Bid {
            blindedBid: blindedBid,
            deposit: msg.value,
        };

        addBid(getSender(), bid);
    }

    fn reveal(values: [u64; 5], fakes: [bool; 5], secrets: [b256; 5]) {
        require(storage.biddingEnd < block.timestamp);
        require(storage.revealEnd > block.timestamp);

        let length = getAmountOfBids(getSender());
        require(length == values.length);
        require(length == fakes.length);
        require(length == secrets.length);

        let refund;
        let i = 0;
        while i < length {
            let bidToCheck: Bid = getBid(getSender(), i);
            let (value, fake, secret) = (values[i], fakes[i], secrets[i]);
            // hash part is pseudocode
            if bidToCheck.blindedBid != hash(value, pair, secret, HashMethod::keccak256) {            
            } else {
                refund += bidToCheck.deposit;
                if (!fake && bidToCheck.deposit >= value) {
                    if (placeBid(getSender(), value)) {
                        refund -= value;
                    };
                };

                setBid(getSender(), ~Bid::empty(), i);


            };
            i = i + 1;
        };
        let sender = getSender();
        transfer_to_output(amount, ETH, getSender());
    }

    fn withdraw() {
        let amount = getPendingReturns(getSender());
        if amount > 0 {
            addPendingReturns(getSender(), 0);
            transfer_to_output(amount, ETH, getSender());
        };
    }

    fn auctionEnd() {
        require(!storage.ended);
        require(storage.revealEnd < block.timestamp);

        storage.ended = true;
        transfer_to_output(storage.highestBid, ETH, storage.beneficiary);
    }
}

fn getSender() -> Address {
    if let Sender::Address(addr) = msg_sender().unwrap() {
        addr
    } else {
        revert(0);
    };
}

fn placeBid(addy: Address, value: u64) -> bool {
    if value <= storage.highestBid {
        return false;
    };
    if storage.highestBidder != ~Address::from(0x0000000000000000000000000000000000000000000000000000000000000000) {
        addPendingReturn(storage.highestBidder, storage.highestBid);
    };
    storage.highestBidder = addy;
    storage.highestBid = value;
    return true;
}

struct Bid {
    blindedBid: b256,
    deposit: u64,
}

impl Bid {
    fn empty() -> Bid {
        Bid {
            blindedBid: ~Address::from(0x0000000000000000000000000000000000000000000000000000000000000000),
            deposit: 0,
        }
    }
}