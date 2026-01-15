import * as fs from 'fs';
import * as path from 'path';
/**
 * Detect project type and suggest run command.
 */
export function detectProjectType(directory) {
    const configFiles = [];
    let type = 'unknown';
    let suggestedCommand = null;
    // Check for package.json (Node.js)
    const packageJsonPath = path.join(directory, 'package.json');
    if (fs.existsSync(packageJsonPath)) {
        configFiles.push('package.json');
        type = 'nodejs';
        try {
            const packageJson = JSON.parse(fs.readFileSync(packageJsonPath, 'utf-8'));
            const scripts = packageJson.scripts || {};
            if (scripts.dev) {
                suggestedCommand = 'npm run dev';
            }
            else if (scripts.start) {
                suggestedCommand = 'npm start';
            }
            else if (scripts.serve) {
                suggestedCommand = 'npm run serve';
            }
        }
        catch {
            suggestedCommand = 'npm start';
        }
    }
    // Check for Cargo.toml (Rust)
    if (fs.existsSync(path.join(directory, 'Cargo.toml'))) {
        configFiles.push('Cargo.toml');
        if (type === 'unknown') {
            type = 'rust';
            suggestedCommand = 'cargo run';
        }
    }
    // Check for Package.swift (Swift)
    if (fs.existsSync(path.join(directory, 'Package.swift'))) {
        configFiles.push('Package.swift');
        if (type === 'unknown') {
            type = 'swift';
            suggestedCommand = 'swift run';
        }
    }
    // Check for pyproject.toml (Python)
    if (fs.existsSync(path.join(directory, 'pyproject.toml'))) {
        configFiles.push('pyproject.toml');
        if (type === 'unknown') {
            type = 'python';
            suggestedCommand = 'python -m pytest';
        }
    }
    // Check for requirements.txt (Python)
    if (fs.existsSync(path.join(directory, 'requirements.txt'))) {
        configFiles.push('requirements.txt');
        if (type === 'unknown') {
            type = 'python';
            suggestedCommand = 'python main.py';
        }
    }
    // Check for go.mod (Go)
    if (fs.existsSync(path.join(directory, 'go.mod'))) {
        configFiles.push('go.mod');
        if (type === 'unknown') {
            type = 'go';
            suggestedCommand = 'go run .';
        }
    }
    // Check for Makefile
    if (fs.existsSync(path.join(directory, 'Makefile'))) {
        configFiles.push('Makefile');
        if (type === 'unknown') {
            type = 'makefile';
            suggestedCommand = 'make run';
        }
    }
    return {
        type,
        suggestedCommand,
        configFiles,
    };
}
//# sourceMappingURL=projectDetection.js.map