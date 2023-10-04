struct Royalty {
    marketplaceFeeAddress: Address;
    marketplaceNumerator: Int as uint32; // TEP-66 says numerator and denominator are contained in uint16, but reference contract uses uint32
    marketplaceDenominator: Int as uint32;

    royaltyAddress: Address;
    royaltyNumerator: Int as uint32;
    royaltyDenominator: Int as uint32;
}

struct OfferParameters {
    type: Int = 0x4f46464552;
    isComplete: Bool;
    createdAt: Int as uint32;
    finishAt: Int as uint32;
    marketplaceAddress: Address; // aka admin address
    nftAddress: Address;
    offerOwnerAddress: Address;
    fullPrice: Int as coins;
    marketplaceFeeAddress: Address;
    marketplaceNumerator: Int as uint32; 
    marketplaceDenominator: Int as uint32;
    royaltyAddress: Address;
    royaltyNumerator: Int as uint32;
    royaltyDenominator: Int as uint32;
    profitPrice: Int as coins;
}

message(555) Fix {
    message: Cell;
    mode: Int as uint8;
}
message(3) CancelOffer{
    cs: Slice as remaining;
}

message(0x5fcc3d14) NftTransfer {
    queryId: Int as uint64;
    newOwner: Address;
    responseDestination: Address;
    customPayload: Cell? = null;
    forwardAmount: Int as coins;
    forwardPayload: Slice as remaining;
}

message(0x05138d91) NftOwnershipAssigned {
    queryId: Int as uint64;
    prevOwner: Address;
    forwardPayload: Slice as remaining;
}

@name(muldiv)
native mulDiv(a: Int, b: Int, c: Int): Int;

contract NftOffer {
    const creationGas: Int = ton("0.1");
    const addValueGas: Int = ton("0.02");
    const nftTransferGas: Int = ton("1");
    const forwardAmount: Int = ton("0.001");
    const reserveValue: Int = ton("0.001");
    isComplete: Bool = false;
    createdAt: Int as uint32;
    finishAt: Int as uint32;
    marketplaceAddress: Address; // aka admin address
    nftAddress: Address;
    offerOwnerAddress: Address;
    fullPrice: Int as coins;
    fees: Royalty;
    // can_deploy seems to be useless here

    init(finishAt: Int, marketplaceAddress: Address, nftAddress: Address, offerOwnerAddress: Address, marketplaceFeeAddress: Address, marketplaceNumerator: Int, marketplaceDenominator: Int, royaltyAddress: Address, royaltyNumerator: Int, royaltyDenominator: Int) {
        self.createdAt = now();
        self.finishAt = finishAt;
        self.marketplaceAddress = marketplaceAddress;
        self.nftAddress = nftAddress;
        self.offerOwnerAddress = offerOwnerAddress;
        self.fullPrice = myBalance();
        self.fees = Royalty {
            marketplaceFeeAddress: marketplaceFeeAddress,
            marketplaceNumerator: marketplaceNumerator,
            marketplaceDenominator: marketplaceDenominator,
            royaltyAddress: royaltyAddress,
            royaltyNumerator: royaltyNumerator,
            royaltyDenominator: royaltyDenominator
        };
    }

    receive(msg: Fix) {
        require(self.isComplete, "Is not completed");
        require(sender() == self.marketplaceAddress, "Invalid sender");
        nativeSendMessage(msg.message, msg.mode);
    }
    receive(msg: CancelOffer) {
        let ctx: Context = context();
        if (ctx.sender == self.marketplaceAddress) {
            let coins: Int = msg.cs.loadCoins();
            if (coins > ton("0.5")) {
                coins = ton("0.5");
            }
            send(SendParameters{
                to: self.marketplaceAddress,
                value: coins,
                mode: SendPayGasSeparately,
                body: "Offer cancel fee".asComment()
            });
        }
        else {
            require(ctx.sender == self.offerOwnerAddress, "Invalid Sender");
        }
        nativeReserve(self.reserveValue, 0);

        send(SendParameters{
            to: self.offerOwnerAddress,
            value: 0,
            mode: SendRemainingBalance
        });
        self.isComplete = true;
    }
    receive(msg: NftOwnershipAssigned) {
        let ctx: Context = context();
        if (ctx.sender != self.nftAddress || ctx.value < self.nftTransferGas || self.isComplete) {
            send(SendParameters{
                to: ctx.sender,
                value: 0,
                mode: SendRemainingValue,
                body: NftTransfer{queryId: msg.queryId, newOwner: msg.prevOwner, responseDestination: msg.prevOwner, forwardAmount: self.forwardAmount, forwardPayload: emptySlice()}.toCell()
            });
            return;
        }
        let royaltyAmount: Int = self.getPercent(self.fullPrice, self.fees.royaltyNumerator, self.fees.royaltyDenominator);
        if (royaltyAmount > 0) {
            send(SendParameters{
                to: self.fees.royaltyAddress,
                value: royaltyAmount,
                mode: SendPayGasSeparately
            });
        }
        let marketplaceAmount: Int = self.getPercent(self.fullPrice, self.fees.marketplaceNumerator, self.fees.marketplaceDenominator);
        if (marketplaceAmount > 0) {
            send(SendParameters{
                to: self.fees.marketplaceFeeAddress,
                value: marketplaceAmount,
                mode: SendPayGasSeparately
            });
        }

        send(SendParameters{
            to: msg.prevOwner,
            value: self.fullPrice - royaltyAmount - marketplaceAmount,
            mode: SendPayGasSeparately
        });

        nativeReserve(self.reserveValue, 0);

        send(SendParameters{
            to: ctx.sender,
            value: 0,
            mode: SendRemainingBalance,
            body: NftTransfer{queryId: msg.queryId, newOwner: self.offerOwnerAddress, responseDestination: self.offerOwnerAddress, forwardAmount: self.forwardAmount, forwardPayload: emptySlice()}.toCell()
        });
        self.isComplete = true;
    }
    receive() {
        let ctx: Context = context();
        require(ctx.sender == self.offerOwnerAddress, "Invalid sender");
        require(ctx.value > self.addValueGas, "Invalid value");
        self.fullPrice = ctx.value - self.addValueGas;
    }

    external("Cancel") {
        require(!self.isComplete, "Already completed");
        require(now() > self.finishAt, "Not expired");
        acceptMessage();
        nativeReserve(self.reserveValue, 0);
        send(SendParameters{
            to: self.offerOwnerAddress,
            value: 0,
            mode: SendRemainingBalance,
            bounce: false,
            body: "Offer expired".asComment()
        });
        self.isComplete = true;
    }

    fun getPercent(a: Int, numerator: Int, denominator: Int): Int {
        if (denominator == 0) {
            return 0;
        }
        return mulDiv(a, numerator, denominator); // muldiv(muldiv(a, numerator, 1000000000), 1000000000, denominator) = muldiv(a, numerator, denominator)
    }
    get fun get_offer_data(): OfferParameters {
        let profitPrice: Int = self.fullPrice - self.getPercent(self.fullPrice, self.fees.royaltyNumerator, self.fees.royaltyDenominator) - self.getPercent(self.fullPrice, self.fees.marketplaceNumerator, self.fees.marketplaceDenominator);
        return OfferParameters{
            isComplete: self.isComplete,
            createdAt: self.createdAt,
            finishAt: self.finishAt,
            marketplaceAddress: self.marketplaceAddress,
            nftAddress: self.nftAddress,
            offerOwnerAddress: self.offerOwnerAddress,
            fullPrice: self.fullPrice,
            marketplaceFeeAddress: self.fees.marketplaceFeeAddress,
            marketplaceNumerator: self.fees.marketplaceNumerator,
            marketplaceDenominator: self.fees.marketplaceDenominator,
            royaltyAddress: self.fees.royaltyAddress,
            royaltyNumerator: self.fees.royaltyNumerator,
            royaltyDenominator: self.fees.royaltyDenominator,
            profitPrice: profitPrice
        };
    }
}
