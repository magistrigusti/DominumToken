import { toNano } from '@ton/core';
import { Allodium } from '../wrappers/Allodium';
import { NetworkProvider } from '@ton/blueprint';

export async function run(provider: NetworkProvider) {
    const allodium = provider.open(await Allodium.fromInit());

    await allodium.send(
        provider.sender(),
        {
            value: toNano('0.05'),
        },
        {
            $$type: 'Deploy',
            queryId: 0n,
        }
    );

    await provider.waitForDeploy(allodium.address);

    // run methods on `allodium`
}
