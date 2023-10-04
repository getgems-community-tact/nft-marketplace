import { toNano } from 'ton-core';
import { NftOffer } from '../wrappers/NftOffer';
import { NetworkProvider } from '@ton-community/blueprint';

export async function run(provider: NetworkProvider) {
    const nftOffer = provider.open(await NftOffer.fromInit());

    await nftOffer.send(
        provider.sender(),
        {
            value: toNano('0.05'),
        },
        {
            $$type: 'Deploy',
            queryId: 0n,
        }
    );

    await provider.waitForDeploy(nftOffer.address);

    // run methods on `nftOffer`
}
