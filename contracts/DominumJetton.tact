import "@stdlib/ownable";
import "./messages";

//              npx blueprint build


contract DominumJetton with Dominum {
    total_supply: Int as coins;
    owner: Address;
    content: Cell;
    mintable: Bool;
    max_supply: Int as coins;

    init(owner: Address, content: Cell, max_supply: Int) {
        self.total_supply = 0;
        self.owner = owner;
        self.mintable = true;
        self.content = content;
        self.max_supply = max_supply;
    }

    receive(msg: MintMining) {
        let ctx: Context = context();
        require(ctx.sender == self.owner, "Not Owner");
        require(self.mintable, "Can't Mint Anymore");
        self.mint(msg.receiver, msg.amount, self.owner);
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
    max_supply: Int;

    receive(msg: TokenUpdateContent) {
        self.requireOwner();
        self.content = msg.content;
    }

    receive(msg: TokenBurnNotification) {
        self.requireWallet(msg.owner);
        self.totalSupply = self.totalSupply - msg.amount;

        if (msg.response_destination != null) {
            send(SendParameters{
                to: msg.response_destination!!,
                value: 0,
                bounce: false,
                mode: SendRemainingValue + SendIgnoreErrors,
                body: TokenExcesses {
                    query_id: msg.queryId
                }.toCell()
            });
        }
    } 

    fun mint(to: Address, amount: Int, response_destination: Address) {
        require(self.totalSupply + amount <= self.max_supply, "The total supply will be overlapping");
        self.totalSupply = self.totalSupply + amount;
        
        let winit: StateInit = self.getJettonWalletInit(to);
        send(SendParameters {
            to: contractAddress(winit),
            value: 0,
            bouce: false,
            mode: TokenTransferInternal {
                query_id: 0n,
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

        let fwdFee: Int = ctx.readForwardFee() + ctx.readForwardFee();  
        let final: Int =  2 * self.gasConsumption + self.minTonsForStorage + fwdFee;
        require(ctx.value > min(final, ton("0.01")), "Invalid value!!"); 

        self.balance = self.balance - msg.amount;
        require(self.balance >= 0, "Invalid balance");

        let init: StateInit = initOf DominumWallet(self.master, msg.detination);
        let walletAddres: Address = contractAddress(init);
        send(SendParameters {
            to: walletAddress,
            value: 0,
            mode: SendRemainingValue,
            bounce: false,
            body: TokenTransferInternal {
                query_id: msg.query_id,
                amount: msg.amount,
                from: self.owner,
                response_destination: msg.response_destination,
                forward_ton_amount: msg.forward_ton_amount,
                forward_payload: msg.forward_payload
            }.toCell(),

            code: init.code,
            data: init.data
        });

        
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
        let fwdFee: Int= ctx.readForwardFee();
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
                to: msg.response_destination,
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

        let fwdFee: Int = ctxreadForwardFee();
        require(ctx.value > fwdFee + 2 * self.gasConsuption + self.minTonsForStorage, "Invalid value - Burn");

        send(SendParameters {
            to: self.master,
            value: 0,
            mode: SendRemainingValue,
            bounce: true,
            body: TokenBurnNotification {
                query_id: msg.query_id,
                amount: msg.amount,
                owner: self.owner,
                response_destination: self.owner
            }.toCell()
        });
    }

    get fun msgValue(value: Int): Int {
        let msgValue: Int = value;
        let tonBalanceBeforeMsg: Int = myBalance() - msgValue;
        let storageFee: Int = self.minTonsForStorage - min(tonBalanceBeforeMsg, self.minTonsForStorage);
        msgValue = msgValue - (storageFee + self.gasConsumption);
        return msgValue;
    }

    get fun get_wallet_data(): JettonWalletData {
        return JettonWalletData {
            balance: self.balance,
            owner: self.owner,
            master: self.master,
            code: (initOf DominumWallet(self.master, self.owner)).code
        };
    }

    bounced(src: bounced<TokenTransferInternal>) {
        self.balance = self.balance + src.amount;
    }

    bounced(src: bounced<TokenBurnNotification>) {
        self.balance = self.balance + src.amount;
    }

}   