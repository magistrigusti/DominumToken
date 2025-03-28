import { CompilerConfig } from '@ton/blueprint';

export const compile: CompilerConfig = {
    lang: 'tact',
    target: 'contracts/allodium.tact',
    options: {
        debug: true,
    },
};
