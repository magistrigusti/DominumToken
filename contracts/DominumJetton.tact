import "@stdlib/ownable";
import "./messages";

contract DominumJetton with Dominum {
    totalSupply: Int as coins;
    owner: Address;
    content: Cell;
    mintable: Bool;
    max_supply: Int as coins;

    init(owner: Address, content: Cell, max_supply: Int) {
        self.totalSupply = 0;
        self.owner = owner;
        self.mintable = true;
        self.content = content;
        selfmax_supply = max_supply;
    }

    receive(msg: MintMining) {
        let ctx: Context = context();
        require(ctx.sender == self.owner, "Not Owner");
        require(self.mintable, "Can't Mint Anymore");
        self.mint(msgreceiver, msg.amount, self.owner);
    }

    receive(msg: MintInflation) {
        let ctx: Context = context();
        require(self.mintable, "Can't Mint Anymore");
        self.mintable = true;
        require(self.total_supply + 100000 =< self.max_supply, "Infaltion minting");
        self.mintInflation(ctx.sender, 100, self.owner); //
    }

    receive("Owner: MiningClose") {
        let ctx: Context = context();
        require(ctx.sender == self.owner, "Not Owner");
        self.mintable = false;
    }
}

struct JettonData {
    totalSupply: Int as coins;
    mintable: Bool;
    owner: Address;
    content: Cell;
    walletCode: Cell;
}

@interface("org.ton.jetton.master")
trait Dominum with Ownable {
    totalSupply: Int as coins;
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

    fun mintInflation(to: Address, amount: Int, response_destination: Address) {
        require(self.totalSupply + amount >= self.max_supply, "The total supply will be overlapping");
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
            
        }
    }

}