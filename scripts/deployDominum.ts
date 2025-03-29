// 📦 Скрипт деплоя DominumMinter с учётом NFT, инфляции и полного контента
import { beginCell, toNano, TonClient, WalletContractV4, internal, fromNano, Address } from "@ton/ton";
import { getHttpEndpoint } from "@orbs-network/ton-access";
import { mnemonicToPrivateKey } from "@ton/crypto";
import { DominumMinter, storeMintMining } from "../output/DominumMinter";
import "dotenv/config";

const main = async () => {
    // 🔐 Получаем мнемонику
    const mnemonics = process.env.MNEMONICS;
    if (!mnemonics || mnemonics.split(" ").length !== 24) throw new Error("MNEMONICS должно содержать 24 слова");

    // 🌐 Сеть и endpoint
    const network = process.env.NETWORK ?? "testnet";
    if (!["mainnet", "testnet"].includes(network)) throw new Error("NETWORK должен быть 'mainnet' или 'testnet'");
    const endpoint = await getHttpEndpoint({ network });
    const client = new TonClient({ endpoint });

    // 🔑 Ключи и кошелёк
    const keyPair = await mnemonicToPrivateKey(mnemonics.split(" "));
    const wallet = WalletContractV4.create({ workchain: 0, publicKey: keyPair.publicKey });
    const walletContract = client.open(wallet);

    // 📊 Подгружаем параметры из .env
    const supply = toNano(process.env.JETTON_SUPPLY ?? "50000000");
    const burnTax = Number(process.env.BURN_TAX ?? 5); // 0.05% в сотых долях процента
    const poolAddress = Address.parse(process.env.POOL_ADDRESS!);
    const inflationAddress = Address.parse(process.env.INFLATION_ADDRESS!);
    const nftRegistry = Address.parse(process.env.NFT_REGISTRY!);

    // 🏗 Создаём контракт DominumMinter
    const dominumMinter = client.open(
        await DominumMinter.fromInit({
            admin: wallet.address,
            content: beginCell().storeStringTail(process.env.JETTON_DESCRIPTION ?? "Allodium Token").endCell(),
            wallet_code: DominumMinter.package.wc,
            max_supply: supply,
            burn_percent: burnTax,
            minting_closed: false,
            pool_address: poolAddress,
            inflation_address: inflationAddress,
            nft_registry: nftRegistry,
        })
    );

    const deployAmount = toNano("0.15"); // С запасом на деплой и gas

    // ⛏️ Создаём тело сообщения MintMining
    const mintMsg = storeMintMining({
        $$type: "MintMining",
        query_id: 0n,
        ton_amount: supply,
        receiver: wallet.address,
    });

    const body = beginCell().store(mintMsg).endCell();

    // 📡 Готовим отправку
    const seqno = await walletContract.getSeqno();
    const balance = await walletContract.getBalance();
    console.log("Баланс деплоера:", fromNano(balance), "TON");

    await walletContract.sendTransfer({
        seqno,
        secretKey: keyPair.secretKey,
        messages: [
            internal({
                to: dominumMinter.address,
                value: deployAmount,
                init: {
                    code: DominumMinter.init.code,
                    data: DominumMinter.init.data,
                },
                body,
            }),
        ],
    });

    console.log("✅ DominumMinter отправлен на деплой:", dominumMinter.address.toString());
    console.log(`🔗 Проверка: https://${network}.tonviewer.com/${dominumMinter.address.toString({ urlSafe: true })}`);
};

void main();
