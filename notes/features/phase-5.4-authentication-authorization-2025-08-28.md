# Phase 5.4: Authentication & Authorization System Planning Document
*Created: 2025-08-28*

## Problem Statement

The SWE-bench-Elixir system has a basic Ash Authentication infrastructure in place but requires comprehensive enhancement to implement role-based access control, advanced authentication methods, usage limiting, and audit logging capabilities. The current system provides password-based authentication with email confirmation, but lacks the security infrastructure needed for production deployment with clear admin/public role separation.

### Impact Analysis

**Current State:**
- Basic password authentication with email confirmation through Ash Authentication
- Token management via SweBench.Accounts.Token resource  
- Simple LiveView authentication hooks for user session management
- No role-based access control or permission system
- No OAuth2 integration or two-factor authentication
- No usage limiting or audit logging capabilities
- No session management beyond basic token authentication

**Required Enhancements:**
- Multi-factor authentication including OAuth2 (GitHub, Google) and 2FA
- Comprehensive role-based authorization with admin/public user separation
- Advanced session management with timeouts, renewal, and analytics
- Usage limiting system with tier-based quotas and real-time tracking
- Comprehensive audit logging for administrative actions
- Integration with LiveView component system for role-based rendering

**Impact Without Enhancement:**
- Security vulnerabilities in production deployment
- No way to restrict evaluation execution to authorized admin users
- Lack of usage monitoring and quota management
- No audit trail for administrative actions
- Poor user experience with limited authentication options
- Inability to scale authentication system for multiple user tiers

**Impact With Enhancement:**
- Production-ready security infrastructure with comprehensive authentication
- Clear separation of admin privileges (evaluation execution) vs public access (result viewing)
- Advanced session management providing security and user experience
- Usage monitoring and quota system enabling sustainable resource management
- Complete audit trail for compliance and security monitoring
- Seamless integration with LiveView architecture for responsive, role-aware interfaces

## Solution Overview

### Design Decisions

**Enhanced Ash Authentication Architecture:**
- Extend existing SweBench.Accounts.User resource with role attributes and OAuth2 strategies
- Integrate Guardian JWT for enhanced token management alongside existing Ash tokens
- Implement OAuth2 strategies for GitHub and Google authentication
- Add two-factor authentication support using TOTP/authenticator apps
- Maintain backward compatibility with existing password authentication

**Role-Based Authorization Framework:**
- Admin role: Full system access including evaluation execution, user management, system configuration
- Public role: Read-only access to results, visualizations, and public dataset information
- Role-based LiveView component rendering using assigns and conditional templates
- Policy-based access control using Ash.Policy.Authorizer for fine-grained permissions

**Advanced Session Management:**
- Multi-tier session storage combining Phoenix session and database persistence
- Configurable session timeouts with automatic renewal for active users
- Session analytics tracking user activity patterns and login locations
- Session management interface for users to view and revoke active sessions
- Integration with real-time event system for live session status updates

**Usage Limiting System:**
- Tier-based user quotas (free tier, premium tier, admin unlimited)
- Sliding window evaluation tracking with Redis-backed counters
- Real-time usage indicators in LiveView components
- Automatic quota reset scheduling and notification system
- Administrative quota management interface with override capabilities

### Architecture Integration

**LiveView Integration:**
- Role-based component rendering using `on_mount` hooks from SweBenchWeb.LiveUserAuth
- Real-time session status updates through Phoenix.PubSub integration
- Dynamic permission checking in LiveView components and event handlers
- Session timeout warnings and renewal prompts in LiveView interface

**Real-Time Event System Integration:**
- Authentication events (login, logout, role changes) broadcast through event system
- Session management events for live status updates across user sessions  
- Usage limit events for real-time quota monitoring and warnings
- Audit log events for comprehensive activity tracking

**Database Schema Design:**
- Extend users table with role, quota_tier, last_activity fields
- New sessions table for persistent session management
- New user_quotas table for usage tracking and limits
- New audit_logs table for comprehensive activity logging
- New oauth_identities table for OAuth2 provider linking

## Agent Consultations Performed

### Elixir-Expert Consultation (Required)
**Query:** Technical guidance for enhancing existing Ash Authentication infrastructure including:
- Guardian JWT integration patterns with existing Ash Authentication tokens
- OAuth2 strategy implementation for GitHub/Google alongside password authentication
- Role/permission attribute design for User resource following Ash patterns
- Session management strategies optimized for LiveView applications
- Two-factor authentication integration approaches using Ash extensions
- Performance considerations for authentication checks in LiveView contexts

**Key Areas:**
- Ash Authentication extension configuration for multiple strategies
- Policy-based authorization implementation using Ash.Policy.Authorizer
- Token management strategy combining Guardian JWT with existing Ash tokens
- LiveView authentication hook optimization for role-based rendering

### Research-Agent Consultation (Required) 
**Query:** Web application security best practices and implementation patterns for:
- OAuth2 implementation security considerations and PKCE flow requirements
- Session management security patterns including token rotation and CSRF protection  
- Two-factor authentication implementation using TOTP standards
- Usage limiting strategies and rate limiting best practices
- Audit logging requirements for security compliance and monitoring
- Phoenix LiveView security considerations for authentication systems

**Key Areas:**
- Industry standard authentication flows and security protocols
- Session security patterns and vulnerability mitigation strategies
- Usage limiting algorithms and implementation approaches
- Audit logging standards and regulatory compliance requirements

### Senior-Engineer-Reviewer Consultation (Required)
**Query:** Production security architecture and scalability considerations for:
- Authentication system performance optimization for high-concurrent LiveView applications
- Database schema design for authentication, sessions, and audit logging at scale
- Caching strategies for permission checks and session validation
- Monitoring and alerting for authentication system health and security events
- Deployment considerations for secrets management and environment configuration
- Long-term maintainability of enhanced authentication architecture

**Key Areas:**
- Scalability implications of authentication architecture decisions
- Performance optimization strategies for authentication in LiveView
- Production security hardening and operational considerations
- Technical debt evaluation and future extensibility planning

## Technical Details

### File Locations and Dependencies

**Core Authentication Files:**
- `/lib/swe_bench/accounts/user.ex` - Primary user resource (enhance with roles, OAuth2)
- `/lib/swe_bench/accounts/token.ex` - Token resource (integrate with Guardian)
- `/lib/swe_bench/accounts.ex` - Accounts domain (add new resources)
- `/lib/swe_bench_web/live_user_auth.ex` - LiveView auth hooks (enhance with roles)
- `/lib/swe_bench_web/auth_overrides.ex` - Authentication overrides (extend)
- `/lib/swe_bench_web/controllers/auth_controller.ex` - Auth controller (OAuth2 endpoints)

**New Files Required:**
- `/lib/swe_bench/accounts/session.ex` - Session resource for persistent session management
- `/lib/swe_bench/accounts/user_quota.ex` - Usage quota tracking resource
- `/lib/swe_bench/accounts/audit_log.ex` - Audit logging resource  
- `/lib/swe_bench/accounts/oauth_identity.ex` - OAuth2 provider identity linking
- `/lib/swe_bench/auth/guardian.ex` - Guardian configuration and token management
- `/lib/swe_bench/auth/two_factor.ex` - Two-factor authentication logic
- `/lib/swe_bench/auth/usage_limiter.ex` - Usage quota and rate limiting
- `/lib/swe_bench/auth/session_manager.ex` - Advanced session management
- `/lib/swe_bench_web/components/auth/` - Authentication-related LiveView components

**Database Migrations Required:**
- Add role, quota_tier, last_activity columns to users table
- Create sessions table for persistent session management
- Create user_quotas table for usage tracking
- Create audit_logs table for activity logging  
- Create oauth_identities table for OAuth2 provider linking
- Add appropriate indexes for performance optimization

**Configuration Updates:**
- `/config/config.exs` - Add Guardian, OAuth2 provider configurations
- `/config/runtime.exs` - OAuth2 secrets and session configuration
- Add environment variables for OAuth2 client IDs and secrets

### Dependencies Analysis

**Current Dependencies (from mix.exs):**
- `{:ash_authentication, "~> 4.0"}` - Core authentication framework
- `{:ash_authentication_phoenix, "~> 2.0"}` - Phoenix integration  
- `{:bcrypt_elixir, "~> 3.0"}` - Password hashing

**Additional Dependencies Required:**
- `{:guardian, "~> 2.3"}` - JWT authentication and token management
- `{:ueberauth, "~> 0.10"}` - OAuth2 authentication framework
- `{:ueberauth_github, "~> 0.8"}` - GitHub OAuth2 strategy
- `{:ueberauth_google, "~> 0.12"}` - Google OAuth2 strategy  
- `{:nimble_totp, "~> 1.0"}` - TOTP two-factor authentication
- `{:redix, "~> 1.3"}` - Redis client for session/quota caching
- `{:hammer, "~> 6.1"}` - Rate limiting and usage quota management

### Authentication Architecture

**Multi-Strategy Authentication Flow:**
1. **Password Authentication:** Enhanced existing Ash Authentication password strategy
2. **OAuth2 Authentication:** GitHub/Google OAuth2 using Ueberauth strategies
3. **Two-Factor Authentication:** TOTP-based 2FA as optional security layer
4. **Token Management:** Dual token system with Ash tokens and Guardian JWT
5. **Session Persistence:** Database-backed session management with Redis caching

**Role-Based Authorization:**
- User roles stored as enum attribute: `:admin`, `:public`
- Ash policies define role-based resource access patterns
- LiveView components use role-based conditional rendering
- Administrative functions protected by admin-only policies

**Session Management Architecture:**
- Phoenix session for basic state management
- Database sessions table for persistent session tracking
- Redis cache for high-performance session validation
- Automatic session cleanup and timeout handling

## Success Criteria

### Functional Requirements

**Authentication Capabilities:**
- [ ] Password authentication maintains existing functionality with enhanced security
- [ ] GitHub OAuth2 authentication integrated with account linking/creation
- [ ] Google OAuth2 authentication integrated with account linking/creation
- [ ] Two-factor authentication optional for all users, required for admin accounts
- [ ] Guardian JWT integration provides enhanced token management capabilities

**Authorization System:**
- [ ] Admin users can execute evaluations and access administrative functions
- [ ] Public users have read-only access to results and visualizations
- [ ] Role-based LiveView component rendering works across all interface components
- [ ] Administrative functions properly protected with role-based policies

**Session Management:**
- [ ] Persistent session tracking with user activity monitoring
- [ ] Configurable session timeouts with automatic renewal for active users
- [ ] Session management interface allows users to view and revoke active sessions
- [ ] Session analytics provide insights into user activity patterns

**Usage Limiting:**
- [ ] Tier-based quota system tracks and enforces evaluation limits
- [ ] Real-time usage indicators display current quota status in LiveView
- [ ] Sliding window evaluation tracking prevents quota gaming
- [ ] Administrative quota management interface enables quota overrides

### Technical Requirements

**Performance:**
- [ ] Authentication checks complete in <50ms for existing sessions
- [ ] OAuth2 authentication flows complete in <5 seconds
- [ ] Session validation scales to 1000+ concurrent users
- [ ] Usage quota checks add <10ms latency to evaluation requests

**Security:**
- [ ] All authentication flows implement CSRF protection
- [ ] OAuth2 implementations use PKCE flow for security
- [ ] Session tokens include proper rotation and expiration
- [ ] Two-factor authentication follows TOTP standards
- [ ] Audit logging captures all security-relevant events

**Integration:**
- [ ] LiveView components seamlessly integrate role-based rendering
- [ ] Real-time event system broadcasts authentication events
- [ ] Existing Phase 5.1-5.3 functionality maintains compatibility
- [ ] Database migrations preserve existing user data integrity

## Implementation Plan

### Phase 1: Foundation Enhancement (Week 1)

**Step 1.1: Extend User Resource with Roles**
- Add role enum attribute to SweBench.Accounts.User resource  
- Add quota_tier enum attribute for usage limiting
- Add last_activity timestamp for session management
- Create database migration for new user attributes
- Update existing policies to incorporate role-based access

**Step 1.2: Implement Guardian JWT Integration**  
- Add Guardian dependency and configuration
- Create SweBench.Auth.Guardian module with token management
- Integrate Guardian tokens alongside existing Ash tokens
- Update authentication flows to provide Guardian JWT tokens
- Create token validation and refresh endpoints

**Step 1.3: Enhance LiveView Authentication**
- Extend SweBenchWeb.LiveUserAuth with role-based hooks
- Add `on_mount(:admin_required)` and `on_mount(:role_check)` hooks  
- Update existing LiveView components for role-based rendering
- Implement role-checking utilities for component conditional logic

### Phase 2: OAuth2 Integration (Week 2)

**Step 2.1: Configure OAuth2 Strategies**
- Add Ueberauth dependencies (GitHub, Google)
- Configure OAuth2 strategies in Ash Authentication
- Set up OAuth2 client credentials and callback URLs
- Create OAuth2 identity linking resource (SweBench.Accounts.OAuthIdentity)

**Step 2.2: Implement OAuth2 Authentication Flow**
- Create OAuth2 authentication actions in User resource
- Implement account creation and linking for OAuth2 users
- Add OAuth2 callback handling in auth controller
- Create OAuth2 authentication components for LiveView interface

**Step 2.3: Account Management Integration**
- Enable linking multiple OAuth2 providers to single accounts
- Implement account unlinking and provider management
- Add OAuth2 provider display in user account settings
- Handle OAuth2 authentication errors and edge cases

### Phase 3: Session Management System (Week 3)

**Step 3.1: Persistent Session Infrastructure**
- Create SweBench.Accounts.Session resource with database persistence
- Implement session creation, validation, and cleanup actions
- Add Redis integration for high-performance session caching
- Create session management utilities and helper functions

**Step 3.2: Advanced Session Features**
- Implement session timeout and automatic renewal logic
- Add session activity tracking and analytics collection
- Create session management interface for user account settings
- Implement session revocation and "logout everywhere" functionality

**Step 3.3: Session Analytics and Monitoring**
- Add session analytics dashboard for administrative users
- Implement session monitoring and alerting for security events
- Create session cleanup jobs for expired and abandoned sessions
- Add session-related audit logging for security tracking

### Phase 4: Two-Factor Authentication (Week 4)

**Step 4.1: TOTP Infrastructure**
- Add NimbleTOTP dependency for two-factor authentication
- Create SweBench.Auth.TwoFactor module for TOTP logic
- Implement 2FA setup and verification actions
- Add 2FA secret generation and QR code functionality

**Step 4.2: Two-Factor Authentication Flow**
- Integrate 2FA into existing authentication strategies
- Create 2FA setup wizard in user account settings
- Implement 2FA verification during login process
- Add 2FA backup codes generation and recovery

**Step 4.3: Administrative 2FA Requirements**
- Enforce 2FA requirement for admin role users
- Implement 2FA status checking and enforcement
- Add administrative 2FA compliance reporting
- Create 2FA emergency bypass for account recovery

### Phase 5: Usage Limiting System (Week 5)

**Step 5.1: Usage Quota Infrastructure**
- Create SweBench.Accounts.UserQuota resource for usage tracking
- Implement quota checking and enforcement logic
- Add Redis-backed sliding window counters for rate limiting
- Create usage quota management utilities

**Step 5.2: Tier-Based Usage System**
- Define usage tiers (free, premium, admin unlimited)
- Implement tier-based quota assignment and management
- Create usage tracking for different evaluation types
- Add automatic quota reset and renewal scheduling

**Step 5.3: Usage Interface and Monitoring**
- Create usage dashboard for users showing current quota status
- Implement real-time usage indicators in LiveView components
- Add administrative quota management interface
- Create usage analytics and reporting for admin users

### Phase 6: Audit Logging & Finalization (Week 6)

**Step 6.1: Comprehensive Audit System**
- Create SweBench.Accounts.AuditLog resource for activity tracking
- Implement audit logging for all authentication and authorization events
- Add audit log viewer for administrative users
- Create audit log retention and cleanup policies

**Step 6.2: System Integration Testing**
- Test authentication system with Phase 5.1-5.3 components
- Verify role-based access control across all interfaces
- Test session management under concurrent usage scenarios
- Validate usage limiting accuracy and performance

**Step 6.3: Production Readiness**
- Configure production secrets management for OAuth2 credentials
- Set up monitoring and alerting for authentication system health
- Create documentation for authentication system administration
- Perform security review and penetration testing

## Notes/Considerations

### Security Considerations

**OAuth2 Security:**
- Use PKCE (Proof Key for Code Exchange) flow for enhanced security
- Implement proper state parameter validation to prevent CSRF attacks
- Validate OAuth2 provider certificates and implement proper error handling
- Store OAuth2 tokens securely with appropriate encryption

**Session Security:**
- Implement proper session token rotation to prevent fixation attacks
- Use secure session storage with appropriate encryption at rest
- Implement session IP binding for additional security (optional)
- Add session anomaly detection for unusual activity patterns

**Two-Factor Authentication:**
- Use cryptographically secure random number generation for TOTP secrets
- Implement proper rate limiting for 2FA verification attempts
- Provide secure backup code generation and storage
- Implement time-based TOTP with appropriate time window tolerance

### Performance Considerations

**Authentication Caching:**
- Cache user role and permission data to avoid repeated database queries
- Use Redis for high-performance session validation
- Implement intelligent cache invalidation for role/permission changes
- Consider connection pooling for database authentication queries

**LiveView Integration:**
- Minimize authentication checks in LiveView event handlers
- Cache role-based component rendering decisions where appropriate
- Use efficient PubSub patterns for real-time authentication events
- Optimize LiveView mount hooks for authentication performance

**Usage Limiting Performance:**
- Use Redis atomic operations for accurate concurrent quota tracking
- Implement efficient sliding window algorithms for usage tracking
- Cache quota status to avoid repeated calculations
- Consider background jobs for quota reset and cleanup operations

### Edge Cases and Error Handling

**OAuth2 Edge Cases:**
- Handle OAuth2 provider service outages gracefully
- Manage OAuth2 account email conflicts with existing accounts
- Handle OAuth2 provider email changes and account relinking
- Implement proper error recovery for failed OAuth2 flows

**Session Management Edge Cases:**
- Handle concurrent session creation and cleanup race conditions
- Manage session cleanup during application deployment and restarts
- Handle session validation during database connectivity issues
- Implement graceful degradation for Redis cache failures

**Usage Limiting Edge Cases:**
- Handle quota enforcement during high concurrent load
- Manage quota tracking consistency across distributed deployments
- Handle quota system recovery after outages or data corruption
- Implement fair usage enforcement to prevent quota gaming

### Future Extensibility

**Additional Authentication Methods:**
- SAML SSO integration for enterprise customers
- API key authentication for programmatic access
- WebAuthn/FIDO2 support for passwordless authentication
- LDAP integration for enterprise directory services

**Enhanced Authorization:**
- Fine-grained permissions beyond admin/public roles
- Team-based access control and collaboration features
- Resource-specific permissions for different evaluation types
- Time-based access control and temporary permissions

**Advanced Usage Management:**
- Usage-based billing and subscription management integration
- Advanced usage analytics and forecasting capabilities
- Team quota sharing and management features
- Usage optimization recommendations and insights

### Testing Strategy

**Unit Testing:**
- Comprehensive test coverage for all authentication actions and strategies
- Mock OAuth2 provider responses for reliable testing
- Test session management logic including concurrent scenarios
- Validate usage limiting accuracy under various load conditions

**Integration Testing:**
- Test complete authentication flows from LiveView interface
- Validate role-based access control across all system components
- Test authentication system integration with real-time event system
- Verify session management integration with Phoenix LiveView

**Security Testing:**
- Penetration testing for authentication vulnerability assessment
- OAuth2 security flow validation and CSRF protection testing
- Session security testing including fixation and hijacking scenarios
- Usage limiting bypass testing and quota gaming prevention

**Performance Testing:**
- Load testing for authentication system under high concurrent usage
- Session management performance testing with large user bases
- Usage limiting performance testing under peak evaluation loads
- LiveView integration performance testing with role-based rendering

### Deployment Considerations

**Environment Configuration:**
- Secure secrets management for OAuth2 client credentials
- Environment-specific session timeout and security configurations
- Redis configuration for session and usage quota caching
- Database connection pool optimization for authentication queries

**Monitoring and Alerting:**
- Authentication failure rate monitoring and alerting
- Session anomaly detection and security event alerting
- Usage quota threshold monitoring and capacity planning alerts
- OAuth2 provider connectivity monitoring and failover alerting

**Operational Procedures:**
- User account recovery procedures for authentication issues
- Emergency access procedures for administrative functions
- Usage quota emergency adjustment procedures
- Authentication system maintenance and update procedures