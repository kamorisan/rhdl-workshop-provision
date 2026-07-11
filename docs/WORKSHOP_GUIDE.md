# Workshop Participant Guide

## Spring Boot to Quarkus Migration with MTA and Developer Lightspeed

Welcome to the migration workshop! This guide will help you migrate the Spring Boot PetClinic application to Quarkus using Migration Toolkit for Applications (MTA) and AI-powered assistance from Red Hat Developer Lightspeed.

## Prerequisites

You should have received:
- OpenShift login credentials (username: `userXX`, password: provided by instructor)
- OpenShift cluster URL
- Dev Spaces Dashboard URL

## Workshop Overview

**Goal:** Migrate the Spring Boot PetClinic application to Quarkus

**Duration:** Approximately 2-3 hours

**What you'll learn:**
- How to use MTA to analyze Spring Boot applications
- How to interpret migration analysis reports
- How to use Developer Lightspeed for AI-powered code migration
- How to apply and customize AI-suggested fixes
- How to build and test a migrated Quarkus application

## Step 1: Access Your Workspace

### 1.1 Log in to OpenShift Console

1. Navigate to the OpenShift Console URL (provided by instructor)
2. Click "workshop_htpasswd"
3. Enter your credentials:
   - Username: `userXX` (e.g., user01)
   - Password: (provided by instructor)

### 1.2 Access Dev Spaces Dashboard

1. From OpenShift Console, use the Application Launcher (9 dots icon) → "Red Hat OpenShift Dev Spaces"
2. Or navigate directly to the Dev Spaces Dashboard URL

### 1.3 Start Your Workspace

1. You should see a workspace named "spring-to-quarkus-userXX"
2. Click "Open" to start your workspace
3. Wait for the workspace to initialize (this may take 2-3 minutes on first start)
4. You'll see a VS Code-like IDE in your browser

## Step 2: Explore the Spring Boot Application

### 2.1 Open the Project

The Spring PetClinic project should already be cloned in your workspace.

1. In the Explorer sidebar, navigate to: `spring-petclinic/`
2. Open `src/main/java/org/springframework/samples/petclinic/PetClinicApplication.java`
3. Review the project structure

### 2.2 Understand the Application

This is a classic Spring Boot application with:
- **Spring MVC** for web layer
- **Spring Data JPA** for data access
- **Thymeleaf** for templates
- **H2 database** (in-memory)
- **Maven** build system

Key packages:
- `owner` - Pet owner management
- `vet` - Veterinarian management
- `visit` - Vet visits

### 2.3 Run the Spring Boot Application (Optional)

To see the original app working:

```bash
cd spring-petclinic
mvn spring-boot:run
```

Access at the "http" endpoint shown in the IDE.

Press Ctrl+C to stop when done.

## Step 3: Analyze with MTA

### 3.1 Open MTA Extension

1. Click the MTA icon in the left sidebar (looks like a compass/analysis icon)
2. Or open View → Command Palette (Ctrl+Shift+P) and type "MTA"

### 3.2 Configure Analysis

1. Click "Add Analysis Configuration"
2. Set the following:
   - **Name:** "Spring to Quarkus"
   - **Source Path:** `/projects/spring-petclinic/src`
   - **Target:** Quarkus
   - **Source:** Spring Boot
   - **Binary Path:** `/projects/spring-petclinic/target/classes` (optional)

3. Click "Save Configuration"

### 3.3 Run Analysis

1. Select your analysis configuration
2. Click "Run Analysis" (▶ icon)
3. Wait for analysis to complete (1-2 minutes)
4. MTA will scan your code and identify migration issues

### 3.4 Review Analysis Report

Once complete, you'll see:
- **Issues Count:** Number of migration issues found
- **Story Points:** Estimated effort
- **Categories:** Mandatory, Optional, Potential

Click on issues to see:
- **File location** with line numbers
- **Issue description**
- **Migration hint**
- **Effort estimate**

Common issues you'll find:
- Spring Boot annotations → Quarkus annotations
- Spring Data JPA → Quarkus Panache
- Spring MVC → Quarkus RESTEasy
- Configuration properties changes
- Dependency changes

## Step 4: Use Developer Lightspeed for Migration

### 4.1 Select an Issue

1. In the MTA Analysis view, click on a migration issue
2. The affected file will open with the issue highlighted

### 4.2 Request AI Fix Suggestion

1. Right-click on the highlighted issue
2. Select "MTA: Get AI Fix Suggestion"
   Or use keyboard shortcut (check Command Palette)

3. Developer Lightspeed (with Solution Server) will:
   - Analyze the issue
   - Check previous solutions in the Solution Server
   - Generate a code fix using the LLM
   - Present the suggested fix

### 4.3 Review the Suggestion

The AI will show:
- **Original code** (what you have)
- **Suggested code** (proposed fix)
- **Explanation** (why this change)
- **Diff view** (changes highlighted)

**Important:** AI suggestions are not always perfect. Review carefully!

### 4.4 Apply or Customize the Fix

You have three options:

**Option 1: Accept**
- Click "Accept" to apply the suggestion as-is

**Option 2: Edit**
- Click "Edit" to modify the suggestion before applying
- Useful for adjusting names, adding your own logic, etc.

**Option 3: Reject**
- Click "Reject" if the suggestion doesn't fit
- Write your own fix manually

### 4.5 Iterate Through Issues

Continue this process:
1. Select next issue
2. Request AI suggestion
3. Review and apply/customize
4. Move to next issue

**Tip:** Start with "Mandatory" issues, then "Optional"

## Step 5: Key Migration Patterns

### 5.1 Spring Boot Application → Quarkus Application

**Before (Spring Boot):**
```java
@SpringBootApplication
public class PetClinicApplication {
    public static void main(String[] args) {
        SpringApplication.run(PetClinicApplication.class, args);
    }
}
```

**After (Quarkus):**
```java
@QuarkusMain
public class PetClinicApplication implements QuarkusApplication {
    public static void main(String[] args) {
        Quarkus.run(PetClinicApplication.class, args);
    }
    
    @Override
    public int run(String... args) throws Exception {
        Quarkus.waitForExit();
        return 0;
    }
}
```

### 5.2 Spring Data JPA Repository → Panache Repository

**Before (Spring Data JPA):**
```java
public interface OwnerRepository extends Repository<Owner, Integer> {
    Collection<Owner> findByLastName(String lastName);
}
```

**After (Quarkus Panache):**
```java
@ApplicationScoped
public class OwnerRepository implements PanacheRepository<Owner> {
    public List<Owner> findByLastName(String lastName) {
        return find("lastName", lastName).list();
    }
}
```

### 5.3 Spring MVC Controller → Quarkus REST

**Before (Spring MVC):**
```java
@Controller
class OwnerController {
    @GetMapping("/owners")
    public String showOwnerList(Model model) {
        model.addAttribute("owners", ownerRepository.findAll());
        return "owners/ownersList";
    }
}
```

**After (Quarkus with Qute templates):**
```java
@Path("/owners")
public class OwnerResource {
    @GET
    @Produces(MediaType.TEXT_HTML)
    public TemplateInstance showOwnerList() {
        return Templates.ownersList(ownerRepository.listAll());
    }
}
```

### 5.4 Configuration Properties

**Before (`application.properties`):**
```properties
spring.datasource.url=jdbc:h2:mem:testdb
spring.jpa.hibernate.ddl-auto=create-drop
```

**After (`application.properties`):**
```properties
quarkus.datasource.jdbc.url=jdbc:h2:mem:testdb
quarkus.hibernate-orm.database.generation=drop-and-create
```

## Step 6: Update Dependencies

### 6.1 Maven pom.xml

Replace Spring Boot parent with Quarkus BOM:

**Before:**
```xml
<parent>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-parent</artifactId>
    <version>3.x.x</version>
</parent>
```

**After:**
```xml
<dependencyManagement>
    <dependencies>
        <dependency>
            <groupId>io.quarkus.platform</groupId>
            <artifactId>quarkus-bom</artifactId>
            <version>3.x.x</version>
            <type>pom</type>
            <scope>import</scope>
        </dependency>
    </dependencies>
</dependencyManagement>
```

### 6.2 Replace Spring Dependencies

**Before:**
```xml
<dependency>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-web</artifactId>
</dependency>
<dependency>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-data-jpa</artifactId>
</dependency>
```

**After:**
```xml
<dependency>
    <groupId>io.quarkus</groupId>
    <artifactId>quarkus-resteasy-reactive</artifactId>
</dependency>
<dependency>
    <groupId>io.quarkus</groupId>
    <artifactId>quarkus-hibernate-orm-panache</artifactId>
</dependency>
```

Developer Lightspeed can suggest these dependency changes too!

## Step 7: Build and Test

### 7.1 Build the Migrated Application

```bash
cd spring-petclinic
mvn clean package
```

Review any compilation errors and fix them.

### 7.2 Run Tests

```bash
mvn test
```

Some tests may need updates for Quarkus. Use MTA and Developer Lightspeed for test migration too.

### 7.3 Run the Quarkus Application

```bash
mvn quarkus:dev
```

Access at the "http" endpoint.

### 7.4 Verify Functionality

Test key features:
- List owners
- Add a new owner
- Add a pet
- Schedule a visit
- View veterinarians

## Step 8: Deploy to OpenShift

### 8.1 Build Container Image

Quarkus can build container images natively:

```bash
mvn package -Dquarkus.container-image.build=true
```

### 8.2 Deploy to Your Namespace

```bash
oc new-app . --name=petclinic-quarkus -n userXX-dev
oc expose svc/petclinic-quarkus -n userXX-dev
```

### 8.3 Get the Route

```bash
oc get route petclinic-quarkus -n userXX-dev
```

Visit the URL to see your migrated app running on OpenShift!

## Step 9: Contribute to Solution Server

As you accept AI suggestions:
- The Solution Server learns from your choices
- Future suggestions improve based on accepted solutions
- Other workshop participants benefit from shared learning
- Your migration patterns help the community

This is the power of shared learning in Developer Lightspeed!

## Tips and Best Practices

### Migration Strategy
1. **Start with infrastructure code** (main class, config)
2. **Migrate data layer** (repositories, entities)
3. **Migrate business logic** (services)
4. **Migrate web layer** (controllers/resources)
5. **Update tests** last

### Using Developer Lightspeed Effectively
- Review every suggestion - don't blindly accept
- Use suggestions as learning tools
- Customize suggestions to fit your coding style
- Provide feedback by accepting/rejecting
- Check Solution Server for similar past fixes

### Common Pitfalls
- Not reviewing AI suggestions
- Forgetting to update dependencies in pom.xml
- Not testing after each migration step
- Ignoring "Optional" issues (some may be important)

## Getting Help

If you're stuck:
1. Check the MTA issue description and hints
2. Review the migration patterns in this guide
3. Ask the workshop instructor
4. Check Quarkus documentation: https://quarkus.io
5. Review MTA documentation

## Completion Checklist

- [ ] Workspace accessed and running
- [ ] Spring Boot app explored
- [ ] MTA analysis completed
- [ ] Migration issues reviewed
- [ ] AI suggestions used for fixes
- [ ] Key components migrated:
  - [ ] Application main class
  - [ ] JPA repositories
  - [ ] Controllers/Resources
  - [ ] Configuration properties
  - [ ] Dependencies in pom.xml
- [ ] Application builds successfully
- [ ] Tests pass
- [ ] Quarkus app runs locally
- [ ] App deployed to OpenShift
- [ ] App verified working

## Next Steps

After completing the migration:
- Explore Quarkus-specific features (live reload, native compilation)
- Learn about Quarkus extensions
- Try native image build: `mvn package -Pnative`
- Explore additional MTA rules and migration paths

Congratulations on completing the migration workshop!
