# Contributing to zease

Thanks for your interest in contributing to zease!

## Philosophy

**Everything in zease must be ZEASY!**

Zease prioritizes **ease of use over raw maximum performance**. The goal is to provide helpers and utilities that make Zig development more convenient and ergonomic, even if that means trading some performance for usability.

### Design Principles

- **Easy to use** - APIs should be intuitive and require minimal boilerplate
- **Easy to understand** - Code should be clear and well-documented
- **Easy to integrate** - Drop-in helpers that just work
- **Safe by default** - Handle the common gotchas for users
- **Performance is important, but not at the cost of usability**

When contributing, ask yourself: "Is this ZEASY to use?" If it requires complex setup, obscure patterns, or lots of manual memory management where it could be automated, it might not be a good fit.

## Getting Started

1. Fork the repository
2. Clone your fork: `git clone https://github.com/YOUR_USERNAME/zease.git`
3. Create a new branch: `git checkout -b feature/your-feature-name`

## Development

### Building and Testing

```bash
# Run all tests
zig build test

# Build the library
zig build
```

### Code Style

- Follow Zig's standard formatting (use `zig fmt`)
- Write clear, descriptive function and variable names
- Add comments for complex logic
- Keep functions focused and modular
- **Prioritize ease of use** - if a helper requires complex setup, consider simplifying it
- **Hide complexity** - manage memory, handle edge cases, provide good defaults

## Making Changes

### Adding New Utilities

When adding new utilities to zease:

1. **Make it ZEASY first:**
   - Would you enjoy using this utility?
   - Does it reduce boilerplate?
   - Is the API intuitive?
   - Does it handle the tedious parts automatically?

2. **Choose the right category:**
   - `src/build/` - Build system utilities
   - `src/concurrency/` - Thread-safe data structures
   - `src/types/` - Type utilities and compile-time helpers
   - Create a new category if needed

3. **Add comprehensive tests:**
   - All new code should have tests
   - For concurrent code, include multi-threaded tests
   - Aim for good coverage of edge cases
   - Tests should also be ZEASY to read and understand

4. **Document your code:**
   - Create documentation in `docs/[category]/[utility].md`
   - Follow the existing documentation format
   - Include usage examples that show how ZEASY it is
   - Link to the source file at the top

5. **Update the README:**
   - Add your utility to the appropriate table in README.md
   - Add a quick example if relevant

### Testing Guidelines

- All tests must pass before submitting a PR
- Add tests for new features
- Update tests if you change existing behavior
- Include both success and failure cases

### Documentation

- Document all public APIs
- Include code examples
- Explain the "why" not just the "what"
- Update existing docs if you change functionality

## Submitting Changes

1. Ensure all tests pass: `zig build test`
2. Format your code: `zig fmt src/`
3. Commit your changes with clear commit messages
4. Push to your fork
5. Open a Pull Request

### Pull Request Guidelines

- Fill out the PR template completely
- Link to any related issues
- Include test results
- Describe what testing you performed
- Keep PRs focused on a single change when possible

## Issue Guidelines

### Reporting Bugs

- Use the bug report template
- Include minimal reproducible code
- Specify your environment (Zig version, OS, etc.)
- Describe expected vs actual behavior

### Requesting Features

- Use the feature request template
- Explain the use case and motivation
- Show proposed API/usage examples
- Consider if it fits zease's philosophy: Is it ZEASY? Does it prioritize ease of use?

### Asking Questions

- Check existing issues and documentation first
- Use the question template
- Provide context about what you're trying to accomplish
- Include relevant code examples

## Code of Conduct

- Be respectful and constructive
- Focus on the code, not the person
- Help others learn and grow
- Keep discussions on-topic

## Questions?

Feel free to open a question issue if you're unsure about anything!

## License

By contributing to zease, you agree that your contributions will be licensed under the same license as the project.
