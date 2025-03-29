import "@stdlib/ownable";
import "./messages";

//              npx blueprint build

contract DominumJetton with Dominum {
    total_supply: Int as coins;
    owner: Address;
    content: Cell;
    mintable: Bool;
    max_supply: Int as coins;


    init(
        owner: Address, content: Cell, max_supply: Int, 
        authorized_minter: Address
        ) {
        self.total_supply = 0;
        self.owner = owner;
        self.mintable = true;
        self.content = content;
        self.max_supply = max_supply;
    }

    receive(msg: MintMining) {
        let ctx: Context = context();
        require(ctx.sender == self.owner, "Not Authorized");
        require(self.mintable, "Can't Mint Anymore");
        self.mint(msg.receiver, msg.amount, ctx.sender);
    }

    receive("Owner: MiningClose") {
        let ctx: Context = context();
        require(ctx.sender == self.owner, "Not Owner");
        self.mintable = false;
    }
}


@interface("org.ton.jetton.master")
trait Dominum with Ownable {
    total_supply: Int as coins;
    mintable: Bool;
    owner: Address;
    content: Cell;
    max_supply: Int as coins;

    receive(msg: TokenUpdateContent) {
        self.requireOwner();
        self.content = msg.content;
    }

    receive(msg: TokenBurnNotification) {
        self.requireWallet(msg.owner);
        self.total_supply = self.total_supply - msg.amount;

        if (msg.response_destination != null) {
            send(SendParameters{
                to: msg.response_destination!!,
                value: 0,
                bounce: false,
                mode: SendRemainingValue + SendIgnoreErrors,
                body: TokenExcesses {
                    query_id: msg.query_id
                }.toCell()
            });
        }
    } 

    fun mint(to: Address, amount: Int, response_destination: Address) {
        require(self.total_supply + amount <= self.max_supply, "The total supply will be overlapping");
        self.total_supply = self.total_supply + amount;
        
        let winit: StateInit = self.getJettonWalletInit(to);
        send(SendParameters {
            to: contractAddress(winit),
            value: 0,
            bounce: false,
            body: TokenTransferInternal {
                query_id: 0,
                amount: amount,
                from: myAddress(),
                response_destination: response_destination,
                forward_ton_amount: 0,
                forward_payload: emptySlice()
            }.toCell(),

            code: winit.code,
            data: winit.data
        });
    }

    fun requireWallet(owner: Address) {
        let ctx: Context = context();
        let winit: StateInit = self.getJettonWalletInit(owner);
        require(contractAddress(winit) == ctx.sender, "Invalid sender");
    }

    virtual fun getJettonWalletInit(address: Address): StateInit {
        return initOf DominumWallet(myAddress(), address);
    }

    get fun get_jetton_data(): JettonData {
        let code: Cell = self.getJettonWalletInit(myAddress()).code;

        return JettonData {
            total_supply: self.total_supply,
            mintable: self.mintable,
            owner: self.owner,
            content: self.content,
            wallet_code: code
        };
    }

    get fun get_wallet_address(owner: Address): Address {
        let winit: StateInit = self.getJettonWalletInit(owner);
        return contractAddress(winit);
    }

}


@interface("org.ton.jetton.wallet")
contract DominumWallet {
    const minTonsForStorage: Int = ton("0.1");
    const gasConsumption: Int = ton("0.05");

    balance: Int as coins;
    owner: Address;
    master: Address;

    init(master: Address, owner: Address) {
        self.balance = 0;
        self.owner = owner;
        self.master = master;
    }

    receive(msg: TokenTransfer) {
        let ctx: Context = context();
        require(ctx.sender == self.owner, "Invalid sender");

        self.balance = self.balance - msg.amount;
        require(self.balance >= 0, "Invalid balance");

        let fee: Int = msg.amount / 2000;
        let amountAfterFee: Int = msg.amount - fee;

        let fwdFee: Int = ctx.readForwardFee();
        let totalRequired: Int = 2 * self.gasConsumption + self.minTonsForStorage + fwdFee;
        require(ctx.value > totalRequired, "Invalid value!");

        let init: StateInit = initOf DominumWallet(self.master, msg.destination);
        let walletAddress: Address = contractAddress(init);
        send(SendParameters {
            to: walletAddress,
            value: 0,
            mode: SendRemainingValue,
            bounce: false,
            body: TokenTransferInternal {
                query_id: msg.query_id,
                amount: amountAfterFee,
                from: self.owner,
                response_destination: msg.response_destination,
                forward_ton_amount: msg.forward_ton_amount,
                forward_payload: msg.forward_payload
            }.toCell(),

            code: init.code,
            data: init.data
        });

        if (fee > 0) {
            send(SendParameters {
                to: self.master,
                value: 0,
                mode: SendRemainingValue,
                bounce: false,
                body: TokenBurnNotification {
                    query_id: msg.query_id,
                    amount: fee,
                    owner: self.owner,
                    sender: ctx.sender,
                    response_destination: null
                }.toCell()
            });
        }

        
    }

    receive(msg: TokenTransferInternal) {
        let ctx: Context = context();

        if (ctx.sender != self.master) {
            let sinit: StateInit = initOf DominumWallet(self.master, msg.from);
            require(contractAddress(sinit) == ctx.sender, "Invalid sender!");
        }

        self.balance = self.balance + msg.amount;
        require(self.balance >= 0, "Invalid balance");

        let msgValue: Int = self.msgValue(ctx.value);
        let fwdFee: Int = ctx.readForwardFee();
        msgValue = msgValue - msg.forward_ton_amount - fwdFee;

        if (msg.forward_ton_amount > 0) {
            send(SendParameters {
                to: self.owner,
                value: msg.forward_ton_amount,
                mode: SendPayGasSeparately + SendIgnoreErrors,
                bounce: false,
                body: TokenNotification {
                    query_id: msg.query_id,
                    amount: msg.amount,
                    from: msg.from,
                    forward_payload: msg.forward_payload
                }.toCell()
            });
        }

        if (msg.response_destination != null) {
            send(SendParameters {
                to: msg.response_destination!!,
                value: msgValue,
                bounce: false,
                body: TokenExcesses {
                    query_id: msg.query_id
                }.toCell(),
                mode: SendIgnoreErrors
            })
        }
    }

    receive(msg: TokenBurn) {
        let ctx: Context = context();
        require(ctx.sender == self.owner, "Invalid sender");

        self.balance = self.balance - msg.amount;
        require(self.balance >= 0, "Invalid balance");

        let fwdFee: Int = ctx.readForwardFee();
        require(ctx.value > fwdFee + 2 * self.gasConsumption + self.minTonsForStorage, "Invalid value - Burn");

        send(SendParameters {
            to: self.master,
            value: 0,
            mode: SendRemainingValue,
            bounce: true,
            body: TokenBurnNotification {
                query_id: msg.query_id,
                amount: msg.amount,
                owner: self.owner,
                sender: context().sender,
                response_destination: msg.response_destination
            }.toCell()
        });
    }

    get fun msgValue(value: Int): Int {
        let msg_value: Int = value;
        let tonBalanceBeforeMsg: Int = myBalance() - msg_value;
        let storageFee: Int = self.minTonsForStorage - min(tonBalanceBeforeMsg, self.minTonsForStorage);
        msg_value = msg_value - (storageFee + self.gasConsumption);
        return msg_value;
    }

    get fun get_wallet_data(): JettonWalletData {
        return JettonWalletData {
            balance: self.balance,
            owner: self.owner,
            master: self.master,
            code: (initOf DominumWallet(self.master, self.owner)).code
        };
    }

    get fun get_wallet_code(): Cell {
        return (initOf DominumWallet(
            myAddress(), myAddress())
            ).code;
}


    bounced(src: bounced<TokenTransferInternal>) {
        self.balance = self.balance + src.amount;
    }

    bounced(src: bounced<TokenBurnNotification>) {
        self.balance = self.balance + src.amount;
    }

}   