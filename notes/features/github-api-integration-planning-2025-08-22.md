# GitHub API Integration Implementation Plan

**Date**: 2025-08-22  
**Feature**: Section 1.3 of Phase 1: GitHub API Integration for Data Collection  
**Status**: Planning Phase  
**Branch**: feature/phase-1.3-github-api-integration

## Problem Statement

SWE-bench-Elixir requires comprehensive GitHub API integration to collect repository data, issues, and pull requests for evaluation task generation. Currently, the system lacks the capability to automatically harvest data from GitHub repositories, which is essential for creating a robust evaluation dataset.

**Why This Matters:**
- **Data Collection Foundation**: GitHub API integration forms the cornerstone of the data collection pipeline, enabling automated harvesting of repository metadata, issue-PR relationships, and code changes
- **Task Generation**: Without GitHub data collection, the system cannot automatically generate evaluation tasks from real-world software engineering scenarios  
- **Evaluation Quality**: Quality evaluation tasks require deep repository analysis including commit history, test modifications, and PR review context
- **Scalability**: Manual data collection doesn't scale to hundreds of repositories needed for comprehensive benchmarking

**Impact Analysis:**
- **Immediate**: Enables automated data collection for initial 5 repositories configured in Phase 1.5
- **Phase Dependencies**: Phase 2 and 3 depend on this GitHub integration for task generation
- **System Architecture**: Forms data persistence foundation that all subsequent phases build upon

## Solution Overview

Implement a comprehensive GitHub API integration system using Elixir's HTTP client ecosystem, designed for production-scale data collection with rate limiting, pagination, and efficient caching. The solution leverages Ash Framework's declarative resource patterns for data modeling and PostgreSQL for persistence.

**High-Level Architecture:**
1. **GitHub API Client Layer**: HTTP client with OAuth authentication, rate limiting, and pagination
2. **Repository Analysis Engine**: Metadata extraction, commit analysis, and dependency detection  
3. **Issue/PR Collection System**: Closed issue harvesting with PR linking and diff extraction
4. **Data Persistence Layer**: Ash resources with Ecto schemas, deduplication, and indexing
5. **Caching Strategy**: Multi-level caching for API responses and processed data

**Key Design Decisions:**
- **HTTP Client**: Use native Elixir HTTP libraries (Tesla/Finch) over external dependencies
- **Authentication**: Implement OAuth flow with secure token management via Ash Authentication
- **Rate Limiting**: Exponential backoff with configurable limits respecting GitHub's API constraints
- **Data Model**: Use Ash resources for declarative data modeling with built-in validation
- **Caching**: Multi-tier caching (memory + database) for API responses and processed results
- **Pagination**: Stream-based processing to handle large result sets efficiently

**Architecture Integration:**
- Integrates with existing Ash Framework for consistent resource patterns
- Uses established PostgreSQL connection for data persistence
- Follows existing error handling and logging patterns from Phase 1.1 and 1.2

## Agent Consultations Performed

**Consultation Status**: Initial consultation attempts made, detailed research pending

- **research-agent**: [PENDING] Research GitHub API libraries (Tentacat vs alternatives), OAuth patterns, rate limiting strategies, and Elixir HTTP client ecosystem
- **elixir-expert**: [PENDING] Guidance on Ash resource design patterns, Ecto schema relationships, data deduplication strategies, and integration with existing authentication system  
- **senior-engineer-reviewer**: [PENDING] Architectural review of HTTP client choice, caching strategies, scalability considerations, and integration patterns

**Note**: Full agent consultations will be completed during implementation phase to ensure optimal technical decisions based on current ecosystem state and project requirements.

## Technical Details

### File Structure and Locations
```
lib/swe_bench/
├── github/
│   ├── client.ex              # GitHub API HTTP client
│   ├── auth.ex                # OAuth authentication handler  
│   ├── rate_limiter.ex        # Rate limiting with backoff
│   ├── paginator.ex           # Pagination handling
│   └── cache.ex               # Response caching layer
├── repositories/
│   ├── analyzer.ex            # Repository metadata analysis
│   ├── repository.ex          # Ash resource for repositories
│   └── commit_history.ex      # Commit analysis logic
├── issues/
│   ├── collector.ex           # Issue and PR data collection
│   ├── issue.ex               # Ash resource for issues
│   ├── pull_request.ex        # Ash resource for pull requests
│   └── diff_parser.ex         # PR diff parsing and analysis
└── tasks/
    ├── instance.ex            # Ash resource for task instances
    └── generator.ex           # Task generation from GitHub data
```

### Configuration Requirements
```elixir
# config/config.exs
config :swe_bench, SweBench.GitHub,
  client_id: System.get_env("GITHUB_CLIENT_ID"),
  client_secret: System.get_env("GITHUB_CLIENT_SECRET"),
  api_base_url: "https://api.github.com",
  rate_limit_buffer: 100,
  cache_ttl: 3600,
  request_timeout: 30_000

# Rate limiting configuration
config :swe_bench, SweBench.GitHub.RateLimiter,
  max_requests_per_hour: 4500,  # Leave buffer for GitHub's 5000/hour limit
  exponential_backoff_base: 2,
  max_backoff_seconds: 300
```

### Dependencies
```elixir
# mix.exs additions
{:tesla, "~> 1.9"},
{:finch, "~> 0.18"},
{:jason, "~> 1.4"},
{:cachex, "~> 3.6"},
{:quantum, "~> 3.5"}  # For scheduled data collection
```

### Database Schema Design
```sql
-- Repositories table
CREATE TABLE repositories (
  id UUID PRIMARY KEY,
  github_id INTEGER UNIQUE NOT NULL,
  name VARCHAR NOT NULL,
  full_name VARCHAR NOT NULL,
  owner VARCHAR NOT NULL,
  description TEXT,
  language VARCHAR,
  stars_count INTEGER,
  forks_count INTEGER,
  has_issues BOOLEAN,
  is_umbrella_project BOOLEAN,
  hex_package_name VARCHAR,
  created_at TIMESTAMP,
  updated_at TIMESTAMP,
  last_analyzed_at TIMESTAMP
);

-- Issues table  
CREATE TABLE issues (
  id UUID PRIMARY KEY,
  repository_id UUID REFERENCES repositories(id),
  github_id INTEGER NOT NULL,
  number INTEGER NOT NULL,
  title VARCHAR NOT NULL,
  body TEXT,
  state VARCHAR NOT NULL,
  created_at TIMESTAMP,
  closed_at TIMESTAMP,
  labels JSONB
);

-- Pull requests table
CREATE TABLE pull_requests (
  id UUID PRIMARY KEY,
  repository_id UUID REFERENCES repositories(id),
  issue_id UUID REFERENCES issues(id),
  github_id INTEGER NOT NULL,
  number INTEGER NOT NULL,
  title VARCHAR NOT NULL,
  body TEXT,
  state VARCHAR NOT NULL,
  diff_content TEXT,
  test_files_modified JSONB,
  created_at TIMESTAMP,
  merged_at TIMESTAMP
);

-- Task instances table
CREATE TABLE task_instances (
  id UUID PRIMARY KEY,
  repository_id UUID REFERENCES repositories(id),
  issue_id UUID REFERENCES issues(id),
  pull_request_id UUID REFERENCES pull_requests(id),
  task_type VARCHAR NOT NULL,
  difficulty_level VARCHAR,
  metadata JSONB,
  created_at TIMESTAMP
);
```

### Indexing Strategy
```sql
-- Performance indexes for common queries
CREATE INDEX idx_repositories_github_id ON repositories(github_id);
CREATE INDEX idx_repositories_full_name ON repositories(full_name);
CREATE INDEX idx_repositories_language ON repositories(language);
CREATE INDEX idx_issues_repository_github ON issues(repository_id, github_id);
CREATE INDEX idx_issues_state ON issues(state);
CREATE INDEX idx_pull_requests_repository ON pull_requests(repository_id);
CREATE INDEX idx_pull_requests_merged_at ON pull_requests(merged_at) WHERE merged_at IS NOT NULL;
CREATE INDEX idx_task_instances_repository ON task_instances(repository_id);
CREATE INDEX idx_task_instances_type_difficulty ON task_instances(task_type, difficulty_level);
```

## Success Criteria

### Critical Completion Requirements

**No feature is complete without comprehensive test coverage:**
- All GitHub API client functions must have unit tests covering success and error scenarios
- Authentication flow must be tested with mock GitHub API responses  
- Rate limiting must be tested under high-frequency request scenarios
- Pagination handling must be tested with large datasets (1000+ items)
- Data persistence must be tested with full repository dataset scenarios
- All Ash resource operations must have corresponding test coverage

### Feature Verification Requirements

**GitHub API Integration:**
- OAuth authentication flow successfully connects to GitHub API
- Rate limiting respects GitHub's API limits with appropriate backoff behavior
- Pagination handles large result sets (1000+ issues/PRs) without memory issues
- Request caching reduces redundant API calls by 80%+ in typical usage
- API client handles network failures gracefully with retry mechanisms

**Repository Analysis:**
- Repository metadata extraction captures all required fields for evaluation
- Commit history analysis identifies test file modifications accurately
- Umbrella project detection works for complex Elixir project structures  
- Hex.pm package information is extracted and linked correctly
- Repository analysis completes within 60 seconds for typical projects

**Issue/PR Data Collection:**
- Closed issues with linked PRs are identified with 95%+ accuracy
- PR diff content is extracted and parsed for code analysis
- Test file modifications are detected and categorized correctly
- Review comments are captured and associated with code changes
- Data collection handles repositories with 10,000+ issues efficiently

**Data Persistence:**
- All collected data is stored in Ash resources with proper validation
- Data deduplication prevents duplicate entries during re-runs
- Database indexes support efficient queries on collected data
- Full repository dataset can be loaded and queried within 2 seconds
- Data integrity constraints prevent orphaned records

**Performance Requirements:**
- Single repository analysis completes within 5 minutes
- System can process 10 repositories concurrently without degradation
- Memory usage stays below 500MB during typical data collection operations
- Database storage is optimized (< 100MB per average repository dataset)

## Implementation Plan

### Step 1: GitHub API Client Foundation

**Expected Behavior and Test Criteria:**
- HTTP client successfully authenticates with GitHub API using OAuth
- Rate limiting prevents API limit violations with exponential backoff
- Request/response cycles complete reliably with proper error handling
- Authentication tokens are managed securely and refreshed automatically

**Implementation Tasks:**
- [ ] Consult research-agent for GitHub API library comparison and OAuth best practices
- [ ] Consult elixir-expert for Tesla/Finch integration patterns with Ash Framework
- [ ] Create `SweBench.GitHub.Client` module with Tesla-based HTTP client
- [ ] Implement OAuth authentication flow with secure token storage
- [ ] Build rate limiting mechanism with configurable limits and backoff
- [ ] Add comprehensive error handling for network and API errors
- [ ] Implement unit tests for authentication, rate limiting, and error scenarios
- [ ] Verify all client tests pass before proceeding to pagination

### Step 2: Request Pagination and Caching

**Expected Behavior and Test Criteria:**
- Pagination automatically handles GitHub's 100-item page limits
- Large result sets (1000+ items) are processed without memory issues
- Caching reduces redundant API calls and improves performance
- Cache invalidation works correctly for updated GitHub data

**Implementation Tasks:**
- [ ] Create `SweBench.GitHub.Paginator` module for automatic page handling
- [ ] Implement streaming pagination to handle large datasets efficiently
- [ ] Build multi-level caching system using Cachex for API responses
- [ ] Add cache key generation and invalidation logic
- [ ] Create comprehensive tests for pagination edge cases (empty results, single page, 1000+ items)
- [ ] Implement caching tests with TTL expiration and invalidation scenarios
- [ ] Verify memory usage stays below 500MB during large dataset processing
- [ ] Verify all pagination and caching tests pass

### Step 3: Repository Analysis Engine

**Expected Behavior and Test Criteria:**
- Repository metadata extraction captures all fields required for evaluation
- Commit history analysis identifies relevant code and test file changes
- Umbrella project detection works for complex Elixir structures
- Analysis completes within 60 seconds for typical repositories

**Implementation Tasks:**
- [ ] Consult elixir-expert for Ash resource design patterns for repositories
- [ ] Create `SweBench.Repositories.Repository` Ash resource with validations
- [ ] Implement `SweBench.Repositories.Analyzer` for metadata extraction
- [ ] Build commit history analysis with test file change detection
- [ ] Add Hex.pm package detection for Elixir-specific repositories
- [ ] Implement umbrella project structure detection
- [ ] Create comprehensive tests for repository analysis across different project types
- [ ] Test analysis performance with large repositories (Phoenix, Ecto size)
- [ ] Verify all repository analysis tests pass including umbrella projects

### Step 4: Issue and PR Data Collection

**Expected Behavior and Test Criteria:**
- Closed issues with linked PRs are identified accurately (95%+ success rate)
- PR diff content is extracted and available for code analysis
- Test file modifications are correctly detected and categorized
- Review comments are associated with specific code changes

**Implementation Tasks:**
- [ ] Create `SweBench.Issues.Issue` and `SweBench.Issues.PullRequest` Ash resources
- [ ] Implement `SweBench.Issues.Collector` for issue-PR relationship detection
- [ ] Build PR diff parsing with `SweBench.Issues.DiffParser`
- [ ] Add test file modification detection from diffs
- [ ] Implement review comment collection and association
- [ ] Create comprehensive tests for issue-PR linking accuracy
- [ ] Test diff parsing with various code change scenarios
- [ ] Test data collection with repositories having 1000+ issues
- [ ] Verify all issue/PR collection tests pass with accuracy requirements

### Step 5: Data Persistence and Task Generation

**Expected Behavior and Test Criteria:**
- All collected GitHub data is stored in properly validated Ash resources
- Data deduplication prevents duplicate entries during collection re-runs  
- Task instances are generated from repository data with proper categorization
- Database queries perform efficiently on collected datasets

**Implementation Tasks:**
- [ ] Create `SweBench.Tasks.Instance` Ash resource for evaluation tasks
- [ ] Implement `SweBench.Tasks.Generator` for task creation from GitHub data
- [ ] Build data deduplication logic for repositories, issues, and PRs
- [ ] Add database migration with optimized indexes for query performance
- [ ] Implement comprehensive data persistence tests with full repository datasets
- [ ] Test task generation logic with various issue-PR scenarios
- [ ] Test deduplication prevents data corruption during re-runs
- [ ] Verify database query performance meets 2-second requirement
- [ ] Verify all data persistence and task generation tests pass

### Step 6: Integration Testing and Performance Validation

**Expected Behavior and Test Criteria:**
- Complete GitHub API integration works end-to-end for real repositories
- System processes multiple repositories concurrently without degradation
- Performance requirements are met for typical and large-scale operations
- Error handling gracefully manages API failures and data inconsistencies

**Implementation Tasks:**
- [ ] Consult test-developer for comprehensive integration testing strategy
- [ ] Create end-to-end integration tests with real GitHub repositories
- [ ] Implement performance tests for concurrent repository processing
- [ ] Build error scenario tests (API failures, network issues, malformed data)
- [ ] Test complete data collection pipeline with 5 initial repositories
- [ ] Validate memory usage, processing time, and storage requirements
- [ ] Run integration tests with production-like data volumes
- [ ] Verify all integration tests pass and performance criteria are met
- [ ] Ensure complete test coverage including error scenarios

## Notes/Considerations

### Edge Cases and Potential Issues

**GitHub API Limitations:**
- Secondary rate limits on specific endpoints (search API has stricter limits)
- Conditional requests and ETags for efficient data fetching
- API deprecations and version changes requiring client updates
- Large repository analysis may hit timeout constraints

**Data Quality Considerations:**
- Issue-PR relationships may not always be explicitly linked in GitHub data
- Diff parsing complexity for binary files, renames, and large changes
- Repository language detection accuracy for multi-language projects
- Stale data issues when repositories are actively developed during collection

**Elixir-Specific Challenges:**
- Umbrella project dependency graphs can be complex to analyze
- Mix.exs parsing for accurate project structure detection
- Hex.pm package data may be inconsistent or outdated
- Test file patterns vary across different Elixir project structures

### Future Improvements and Extensibility

**Enhanced Data Collection:**
- GraphQL API usage for more efficient data fetching
- Webhook integration for real-time repository updates
- Code quality metrics extraction (complexity, test coverage)
- Contributor analysis and maintainer activity patterns

**Performance Optimizations:**
- Database partitioning for large-scale repository data
- Distributed data collection across multiple workers
- Advanced caching strategies with Redis integration
- Incremental updates instead of full repository re-analysis

**Additional Integrations:**
- GitLab and other version control platform support
- Integration with code quality tools (Credo, Dialyzer)
- Link to continuous integration systems for test result correlation
- Package manager integration beyond Hex.pm (NPM for Phoenix LiveView projects)

### Risk Assessment and Mitigation

**High-Risk Areas:**
- **GitHub API Rate Limiting**: Mitigation through careful request planning and caching
- **Data Volume Storage**: Database optimization and partitioning strategies needed
- **Authentication Token Security**: Secure token management and rotation required
- **Network Reliability**: Robust retry mechanisms and graceful degradation needed

**Medium-Risk Areas:**
- **Data Parsing Accuracy**: Comprehensive testing with diverse repository structures
- **Performance Under Load**: Load testing and optimization for concurrent processing
- **Schema Evolution**: Flexible data models to accommodate GitHub API changes

**Monitoring and Observability:**
- API usage metrics and rate limit monitoring
- Data collection success/failure rates tracking
- Performance metrics for repository analysis operations
- Database storage and query performance monitoring

---

This comprehensive planning document provides the foundation for implementing robust GitHub API integration as the cornerstone of SWE-bench-Elixir's data collection capabilities. The systematic approach ensures scalable, maintainable, and well-tested implementation that integrates seamlessly with the existing Ash Framework architecture.