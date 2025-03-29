import { CompilerConfig } from '@ton/blueprint';

export const compile: CompilerConfig = {
    lang: 'tact',
    target: 'contracts/DominumMinter.tact',
    options: {
        debug: true,
    },
};
