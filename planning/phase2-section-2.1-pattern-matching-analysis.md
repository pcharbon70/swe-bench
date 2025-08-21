# Phase 2 Section 2.1: Pattern Matching and Function Clause Analysis

## Problem Statement

ElixirSweBench currently evaluates LLM-generated code only through test execution (PASS/FAIL). This binary evaluation misses the nuanced quality aspects of Elixir code, particularly around pattern matching - a core feature that distinguishes functional programming. LLMs often generate working but non-idiomatic code with poor pattern matching practices:

- Overly complex conditional logic instead of pattern matching
- Non-exhaustive patterns leading to runtime errors
- Poor clause ordering causing unreachable code
- Missing guard clauses or improper guard usage
- Lack of destructuring in function heads

**Impact**: Without pattern matching analysis, we cannot:
1. Award partial credit for good functional programming practices
2. Guide LLMs toward idiomatic Elixir code generation
3. Identify subtle bugs that tests might miss
4. Provide meaningful feedback beyond "tests pass/fail"

## Solution Overview

Build a comprehensive Pattern Matching Analysis Engine that:
1. **Parses Elixir code into AST** for deep structural analysis
2. **Validates pattern exhaustiveness** to prevent runtime errors
3. **Analyzes clause ordering** to detect unreachable code
4. **Scores pattern quality** based on Elixir best practices
5. **Integrates with existing pipeline** to augment test results

### Key Design Decisions

1. **AST-based Analysis**: Use Elixir's native `Code.string_to_quoted/1` for accurate parsing
2. **Static Analysis**: Perform all checks without code execution for safety
3. **Graduated Scoring**: Provide nuanced scores (0-100) rather than binary pass/fail
4. **Modular Architecture**: Separate analyzers for different pattern aspects
5. **Pipeline Integration**: Add as a new stage after ContainerEvaluator

## Technical Details

### File Structure
```
lib/elixir_swe_bench/
├── analyzers/
│   ├── pattern_matching/
│   │   ├── ast_parser.ex           # Core AST parsing and traversal
│   │   ├── exhaustiveness_checker.ex # Pattern completeness validation
│   │   ├── clause_analyzer.ex      # Clause ordering and reachability
│   │   ├── pattern_scorer.ex       # Quality scoring algorithms
│   │   └── pattern_analyzer.ex     # Main orchestrator
│   └── analyzer_supervisor.ex      # Supervises all analyzers
├── pipeline/
│   └── pattern_analysis_stage.ex   # GenStage consumer-producer
└── scoring/
    └── pattern_metrics.ex          # Scoring calculations
```

### Dependencies
- No external dependencies needed (uses Elixir stdlib)
- Integrates with existing GenStage pipeline
- Outputs to existing ResultAnalyzer

### Configuration
```elixir
config :elixir_swe_bench, :pattern_analysis,
  enabled: true,
  weight: 0.3,  # 30% of total score
  thresholds: %{
    exhaustiveness: 0.9,
    clause_quality: 0.8,
    idiomatic_usage: 0.85
  }
```

## Success Criteria

### Functional Requirements
- [ ] Parse any valid Elixir module into analyzable AST
- [ ] Detect non-exhaustive pattern matching with 95% accuracy
- [ ] Identify unreachable clauses with 100% accuracy
- [ ] Score pattern quality on 0-100 scale
- [ ] Process analysis within 100ms per module
- [ ] Generate detailed analysis reports

### Quality Metrics
- [ ] 100% test coverage for all analyzers
- [ ] Handle macro-generated code gracefully
- [ ] Support all Elixir pattern types (literal, variable, structured, pinned)
- [ ] Integrate seamlessly with existing pipeline
- [ ] Provide actionable feedback in reports

## Implementation Plan

### Step 1: AST Parser Foundation
**Goal**: Build robust AST parsing and traversal infrastructure

#### 1.1 Create AST Parser Module
```elixir
defmodule ElixirSweBench.Analyzers.PatternMatching.ASTParser do
  @moduledoc """
  Parses Elixir source code into AST and provides traversal utilities.
  """
end
```
- [ ] Implement `parse_source/1` to convert string to AST
- [ ] Add `extract_functions/1` to find all function definitions
- [ ] Create `extract_patterns/1` to identify all patterns
- [ ] Build `traverse_ast/2` for custom traversals
- [ ] Add error handling for invalid syntax

#### 1.2 Pattern Type Detection
- [ ] Implement pattern classification (literal, variable, tuple, list, map, struct)
- [ ] Add guard detection and extraction
- [ ] Create pattern complexity metrics
- [ ] Build pattern tree representation

#### 1.3 Testing
- [ ] Test with simple function patterns
- [ ] Test with complex nested patterns
- [ ] Test with guard clauses
- [ ] Test error handling for malformed code
- [ ] Benchmark parsing performance

### Step 2: Exhaustiveness Checker
**Goal**: Validate pattern matching completeness

#### 2.1 Create Exhaustiveness Module
```elixir
defmodule ElixirSweBench.Analyzers.PatternMatching.ExhaustivenessChecker do
  @moduledoc """
  Validates that pattern matching covers all possible cases.
  """
end
```
- [ ] Implement `check_function_exhaustiveness/1`
- [ ] Add type inference for pattern domains
- [ ] Create missing pattern detection
- [ ] Build exhaustiveness report generation

#### 2.2 Pattern Coverage Analysis
- [ ] Implement boolean exhaustiveness (true/false)
- [ ] Add atom coverage detection
- [ ] Create tuple pattern analysis
- [ ] Build list pattern coverage (empty, non-empty)
- [ ] Add map/struct key coverage

#### 2.3 Testing
- [ ] Test exhaustive patterns (should pass)
- [ ] Test non-exhaustive patterns (should fail)
- [ ] Test with guard clauses
- [ ] Test with catch-all patterns
- [ ] Test edge cases (empty functions, macros)

### Step 3: Clause Ordering Analyzer
**Goal**: Detect unreachable code and suboptimal ordering

#### 3.1 Create Clause Analyzer Module
```elixir
defmodule ElixirSweBench.Analyzers.PatternMatching.ClauseAnalyzer do
  @moduledoc """
  Analyzes function clause ordering and reachability.
  """
end
```
- [ ] Implement `analyze_clause_order/1`
- [ ] Add subsumption detection (general before specific)
- [ ] Create unreachable clause identification
- [ ] Build optimal ordering suggestions

#### 3.2 Reachability Analysis
- [ ] Implement pattern subsumption algorithm
- [ ] Add guard clause precedence analysis
- [ ] Create clause dependency graph
- [ ] Build reachability report

#### 3.3 Testing
- [ ] Test properly ordered clauses
- [ ] Test unreachable clause detection
- [ ] Test guard clause ordering
- [ ] Test with complex patterns
- [ ] Performance testing with large modules

### Step 4: Pattern Quality Scorer
**Goal**: Score pattern matching quality based on best practices

#### 4.1 Create Pattern Scorer Module
```elixir
defmodule ElixirSweBench.Analyzers.PatternMatching.PatternScorer do
  @moduledoc """
  Scores pattern matching quality based on Elixir idioms.
  """
end
```
- [ ] Implement scoring algorithm (0-100 scale)
- [ ] Add idiomatic pattern detection
- [ ] Create destructuring effectiveness metrics
- [ ] Build pattern vs conditional logic comparison

#### 4.2 Scoring Dimensions
- [ ] Pattern specificity score (specific > general)
- [ ] Destructuring usage score
- [ ] Guard clause appropriateness
- [ ] Pattern clarity and readability
- [ ] Idiomatic Elixir patterns

#### 4.3 Testing
- [ ] Test scoring for excellent patterns (90-100)
- [ ] Test scoring for good patterns (70-89)
- [ ] Test scoring for poor patterns (0-69)
- [ ] Test score consistency
- [ ] Validate scoring weights

### Step 5: Pipeline Integration
**Goal**: Integrate pattern analysis into evaluation pipeline

#### 5.1 Create Pipeline Stage
```elixir
defmodule ElixirSweBench.Pipeline.PatternAnalysisStage do
  use GenStage
  @moduledoc """
  GenStage that performs pattern matching analysis.
  """
end
```
- [ ] Implement GenStage callbacks
- [ ] Add demand management
- [ ] Create result aggregation
- [ ] Build error handling

#### 5.2 Connect to Pipeline
- [ ] Add stage after ContainerEvaluator
- [ ] Configure stage in pipeline supervisor
- [ ] Update result schemas for pattern scores
- [ ] Modify ResultAnalyzer to include pattern metrics

#### 5.3 Testing
- [ ] Integration test with full pipeline
- [ ] Test backpressure handling
- [ ] Test error propagation
- [ ] Performance testing
- [ ] End-to-end validation

### Step 6: Reporting and Visualization
**Goal**: Generate comprehensive pattern analysis reports

#### 6.1 Report Generation
- [ ] Create detailed pattern analysis reports
- [ ] Add pattern quality visualizations
- [ ] Build exhaustiveness coverage maps
- [ ] Generate improvement suggestions

#### 6.2 CLI Integration
- [ ] Add pattern analysis commands
- [ ] Create pattern-only evaluation mode
- [ ] Build pattern report viewing

#### 6.3 Testing
- [ ] Test report generation
- [ ] Validate report accuracy
- [ ] Test CLI commands
- [ ] User acceptance testing

## Current Status

### ✅ Completed
- Project planning and design
- File structure design  
- Integration approach defined
- **Step 1.1: AST Parser Module** ✅
  - Implemented `parse_source/1` to convert string to AST
  - Added `extract_functions/1` to find all function definitions
  - Created `extract_patterns/1` to identify all patterns
  - Built `traverse_ast/2` for custom traversals
  - Added error handling for invalid syntax
- **Step 1.2: Pattern Type Detection** ✅
  - Implemented pattern classification (literal, variable, tuple, list, map, etc.)
  - Added guard detection and extraction
  - Created pattern complexity metrics
- **Step 1.3: Initial Testing** ✅
  - Created comprehensive test suite
  - Tests passing for core functionality
  - Some edge cases need refinement

### 🔄 In Progress
- Step 2: Exhaustiveness Checker

### 📋 Next Steps
1. ✅ Implement AST parser (COMPLETED)
2. Create exhaustiveness checker (IN PROGRESS)
3. Build clause analyzer
4. Develop pattern scorer
5. Integrate with pipeline

### How to Run (once implemented)
```bash
# Run pattern analysis on a file
./elixir_swe_bench analyze-patterns path/to/file.ex

# Run full evaluation with pattern analysis
./elixir_swe_bench evaluate --tasks tasks.json --include-patterns

# View pattern analysis report
./elixir_swe_bench results --pattern-details
```

## Notes and Considerations

### Performance Considerations
- AST parsing is fast but traversal can be expensive
- Cache parsed ASTs when analyzing multiple functions
- Use ETS for pattern coverage tables
- Consider parallel analysis for large modules

### Edge Cases
- Macro-generated code may have non-standard patterns
- External function calls in guards need special handling
- Module attributes in patterns require expansion
- Compile-time vs runtime pattern evaluation

### Future Enhancements
- Machine learning for pattern quality scoring
- Pattern suggestion engine
- Cross-module pattern analysis
- Pattern refactoring suggestions
- Integration with Credo for unified scoring

### Risks and Mitigations
- **Risk**: AST parsing fails on macro-heavy code
  - **Mitigation**: Expand macros before analysis when possible
- **Risk**: Exhaustiveness checking has false positives
  - **Mitigation**: Conservative analysis with confidence scores
- **Risk**: Performance impact on pipeline
  - **Mitigation**: Make analysis optional/configurable

## References
- [Elixir AST Documentation](https://hexdocs.pm/elixir/syntax-reference.html#the-elixir-ast)
- [Pattern Matching Guide](https://elixir-lang.org/getting-started/pattern-matching.html)
- [Exhaustiveness Checking Papers](https://www.cs.tufts.edu/~nr/pubs/match.pdf)
- [Elixir Style Guide](https://github.com/christopheradams/elixir_style_guide)