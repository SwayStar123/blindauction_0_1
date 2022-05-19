contract;

use std::address::Address;
use std::contract_id::ContractId;
use std::hash::*;
use std::chain::auth::{AuthError, Sender, msg_sender};
use std::token::transfer_to_output;
use std::storage::{get, store};
use std::revert::revert;
use std::assert::assert;

abi MyContract {
    fn start_auction(beneficiary: Address, biddingEnd: u64, revealEnd: u64);
    fn bid(blindedBid: b256);
    fn reveal(values: [u64; 5], fakes: [bool; 5], secrets: [b256; 5]);
    fn withdraw();
    fn auction_end();
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

fn add_bid(addy: Address, bid: Bid) {
    let index_slot = sha256((BIDNOS, addy));
    let index = get::<u64>(index_slot);
    store(index_slot, index + 1);
    //hashing is fucked, needs a b256 as a argument, idk how to get that from a tuple or 3 different values
    let storage_slot = sha256((BIDS, addy, index));

    store(storage_slot, bid);
}

//for setting a specific bid index instead of adding a new one ontop
fn set_bid(addy: Address, bid: Bid, index: u64) {
    let storage_slot = sha256((BIDS, addy, index));

    store(storage_slot, bid);
}

fn get_bid(addy: Address, index: u64) -> Bid {
    let storage_slot = sha256((BIDS, addy, index));
    get::<Bid>(storage_slot)
}

fn get_amount_of_bids(addy: Address) -> u64 {
    let index_slot = sha256((BIDNOS, addy));
    get::<u64>(index_slot)
}

const PENDINGRETURNS: b256 = 0x0000000000000000000000000000000000000000000000000000000000000002;

fn add_pending_return(addy: Address, amount: u64) {
    let storage_slot = sha256((PENDINGRETURNS, addy));
    store(storage_slot, amount);
}

fn get_pending_returns(addy: Address) -> u64 {
    let storage_slot = sha256((PENDINGRETURNS, addy));
    get::<u64>(storage_slot)
}

impl MyContract for Contract {
    fn start_auction(beneficiary: Address, biddingEnd: u64, revealEnd: u64) {
        assert(storage.ended);
        storage.ended = false;
        storage.beneficiary = beneficiary;
        storage.biddingEnd = biddingEnd;
        storage.revealEnd = revealEnd;

        storage.highestBidder =  ~Address::from(0x0000000000000000000000000000000000000000000000000000000000000000);
        storage.highestBid = 0;
    }

    fn bid(blindedBid: b256) {
        assert(!storage.ended);
        assert(storage.biddingEnd > block.timestamp);

        let bid = Bid {
            blindedBid: blindedBid,
            deposit: msg.value,
        };

        add_bid(get_sender(), bid);
    }

    fn reveal(values: [u64; 5], fakes: [bool; 5], secrets: [b256; 5]) {
        assert(storage.biddingEnd < block.timestamp);
        assert(storage.revealEnd > block.timestamp);

        // Commented code - unnecessary due to fixed number of bids due to unavailability of dynamic arrays
        // let length = get_amount_of_bids(get_sender());
        // assert(length == values.length);
        // assert(length == fakes.length);
        // assert(length == secrets.length);

        let length = get_amount_of_bids(get_sender());
        //get_amount_of_bids actually returns index not length, so 4 not 5
        assert(length==4);

        let mut refund = 0;
        let mut i = 0;
        while i < length {
            let bidToCheck: Bid = get_bid(get_sender(), i);
            let (value, fake, secret) = (values[i], fakes[i], secrets[i]);
            // hash part is pseudocode
            if bidToCheck.blindedBid != keccak256((value, fake, secret)) {            
            } else {
                refund = refund + bidToCheck.deposit;
                if (!fake && bidToCheck.deposit >= value) {
                    if (place_bid(get_sender(), value)) {
                        refund = refund - value;
                    };
                };

                set_bid(get_sender(), ~Bid::empty(), i);


            };
            i = i + 1;
        };
        let sender = get_sender();
        transfer_to_output(refund, ETH, get_sender());
    }

    fn withdraw() {
        let amount = get_pending_returns(get_sender());
        if amount > 0 {
            add_pending_return(get_sender(), 0);
            transfer_to_output(amount, ETH, get_sender());
        };
    }

    fn auction_end() {
        assert(!storage.ended);
        assert(storage.revealEnd < block.timestamp);

        storage.ended = true;
        transfer_to_output(storage.highestBid, ETH, storage.beneficiary);
    }
}

fn get_sender() -> Address {
    if let Sender::Address(addr) = msg_sender().unwrap() {
        addr
    } else {
        revert(0);
    };
}

fn place_bid(addy: Address, value: u64) -> bool {
    if value <= storage.highestBid {
        return false;
    };
    if storage.highestBidder != ~Address::from(0x0000000000000000000000000000000000000000000000000000000000000000) {
        add_pending_return(storage.highestBidder, storage.highestBid);
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
            blindedBid: 0x0000000000000000000000000000000000000000000000000000000000000000,
            deposit: 0,
        }
    }
}