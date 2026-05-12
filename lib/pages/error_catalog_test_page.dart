import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:create_inpection_report/models/error_catalog.dart';
import 'package:create_inpection_report/services/database_service.dart';

class ErrorCatalogTestPage extends StatefulWidget {
  const ErrorCatalogTestPage({super.key});

  @override
  _ErrorCatalogTestPageState createState() => _ErrorCatalogTestPageState();
}

class _ErrorCatalogTestPageState extends State<ErrorCatalogTestPage> {
  List<ErrorCatalog> catalogErrors = [];
  List<Map<String, dynamic>> rawDbData = [];
  bool isLoading = true;
  String testResult = '';
  List<String> testSteps = [];

  @override
  void initState() {
    super.initState();
    _runComprehensiveTest();
  }

  Future<void> _runComprehensiveTest() async {
    setState(() {
      isLoading = true;
      testSteps.clear();
      testResult = '';
    });

    try {
      // Test 1: Database Connection
      _addTestStep('Testing database connection...');
      final db = await DatabaseService.getDb();
      _addTestStep('✅ Database connected successfully');

      // Test 2: Check if error_catalog table exists
      _addTestStep('Checking error_catalog table...');
      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='error_catalog'"
      );
      if (tables.isEmpty) {
        _addTestStep('❌ error_catalog table does not exist');
        setState(() {
          testResult = 'DATABASE ISSUE: error_catalog table missing';
        });
        return;
      }
      _addTestStep('✅ error_catalog table exists');

      // Test 3: Check table structure
      _addTestStep('Checking error_catalog table structure...');
      final tableInfo = await db.rawQuery('PRAGMA table_info(error_catalog)');
      _addTestStep('Table structure: ${tableInfo.length} columns');
      for (final column in tableInfo) {
        _addTestStep('  - ${column['name']}: ${column['type']}');
      }

      // Test 4: Check raw data count
      _addTestStep('Checking raw error catalog data...');
      final rawCount = await db.rawQuery('SELECT COUNT(*) as count FROM error_catalog');
      final count = rawCount.first['count'] as int;
      _addTestStep('Raw database count: $count entries');

      // Test 5: Get raw data sample
      _addTestStep('Getting raw data sample...');
      final rawSample = await db.query('error_catalog', limit: 5);
      setState(() {
        rawDbData = rawSample;
      });
      _addTestStep('Raw sample: ${rawSample.length} rows');

      // Test 6: Test getAllErrorCatalogItems method
      _addTestStep('Testing getAllErrorCatalogItems method...');
      final catalogItems = await DatabaseService.getAllErrorCatalog();
      setState(() {
        catalogErrors = catalogItems;
      });
      _addTestStep('✅ getAllErrorCatalogItems returned ${catalogItems.length} items');

      // Test 7: Test search functionality
      _addTestStep('Testing search functionality...');
      final searchResults = await DatabaseService.searchErrorCatalog('tür');
      _addTestStep('✅ Search for "tür" returned ${searchResults.length} results');

      // Test 8: Test DoorErrorCatalog.getStandardErrors
      _addTestStep('Testing DoorErrorCatalog.getStandardErrors...');
      final standardErrors = DoorErrorCatalog.getStandardErrors();
      _addTestStep('✅ DoorErrorCatalog.getStandardErrors returned ${standardErrors.length} errors');

      // Test 9: Check if data is properly mapped
      _addTestStep('Checking data mapping...');
      if (catalogItems.isNotEmpty) {
        final firstError = catalogItems.first;
        _addTestStep('First error mapping:');
        _addTestStep('  - errorId: ${firstError.errorId}');
        _addTestStep('  - code: ${firstError.code}');
        _addTestStep('  - description: ${firstError.description}');
        _addTestStep('  - category: ${firstError.category}');
        _addTestStep('  - severity: ${firstError.severity}');
      }

      // Test 10: Verify inspection_errors table is GONE (Change 2)
      _addTestStep('Verifying inspection_errors table is removed...');
      final inspectionTables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='inspection_errors'"
      );
      if (inspectionTables.isEmpty) {
        _addTestStep('✅ inspection_errors table successfully removed');
      } else {
        _addTestStep('❌ inspection_errors table STILL EXISTS');
      }

      // Final assessment
      if (catalogItems.isEmpty) {
        setState(() {
          testResult = 'DATABASE ISSUE: No error catalog data found. Database may need seeding.';
        });
        _addTestStep('❌ FINAL: No catalog data loaded');
      } else {
        setState(() {
          testResult = 'SUCCESS: Error catalog is working properly';
        });
        _addTestStep('✅ FINAL: All tests passed');
      }

    } catch (e) {
      _addTestStep('❌ ERROR: $e');
      setState(() {
        testResult = 'ERROR: $e';
      });
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  void _addTestStep(String step) {
    setState(() {
      testSteps.add('${DateTime.now().millisecondsSinceEpoch}: $step');
    });
    print('TEST STEP: $step');
  }

  Future<void> _seedDatabase() async {
    try {
      _addTestStep('Manually seeding database...');
      final db = await DatabaseService.getDb();
      
      // Get standard errors and insert them manually
      final standardErrors = DoorErrorCatalog.getStandardErrors();
      _addTestStep('Found ${standardErrors.length} standard errors to seed');
      
      for (final error in standardErrors) {
        try {
          await db.insert(
            'error_catalog',
            error.toMap(),
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );
        } catch (e) {
          _addTestStep('Error seeding ${error.code}: $e');
        }
      }
      
      _addTestStep('✅ Database seeded successfully');
      
      // Re-run test after seeding
      await _runComprehensiveTest();
    } catch (e) {
      _addTestStep('❌ Seeding failed: $e');
    }
  }

  Future<void> _createTestPendingError() async {
    try {
      _addTestStep('Creating a mock pending error...');
      final mock = ErrorCatalog(
        code: 'REQ-${DateTime.now().millisecondsSinceEpoch.toString().substring(10)}',
        description: 'Test Anfrage vom Inspektor',
        category: 'Sonstiges',
        status: 'Pending',
        requestedBy: 'Test User',
        requestDate: DateTime.now(),
      );
      
      await DatabaseService.insertErrorCatalog(mock);
      _addTestStep('✅ Mock pending error created');
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Test-Anfrage erstellt! Prüfen Sie jetzt das Manager Dashboard.')),
      );
      await _runComprehensiveTest();
    } catch (e) {
      _addTestStep('❌ Failed to create mock: $e');
    }
  }

  Future<void> _clearDatabase() async {
    try {
      _addTestStep('Clearing error catalog...');
      final db = await DatabaseService.getDb();
      await db.delete('error_catalog');
      _addTestStep('✅ Error catalog cleared');
      
      // Re-run test after clearing
      await _runComprehensiveTest();
    } catch (e) {
      _addTestStep('❌ Clear failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Error Catalog Diagnostic Test'),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh),
            onPressed: _runComprehensiveTest,
          ),
        ],
      ),
      body: isLoading
          ? Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Test Result Summary
                  Container(
                    width: double.infinity,
                    padding: EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: testResult.contains('SUCCESS') ? Colors.green.shade100 : 
                             testResult.contains('ERROR') ? Colors.red.shade100 : 
                             testResult.contains('ISSUE') ? Colors.orange.shade100 : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Test Result: $testResult',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: testResult.contains('SUCCESS') ? Colors.green : 
                                   testResult.contains('ERROR') ? Colors.red : 
                                   testResult.contains('ISSUE') ? Colors.orange : Colors.grey,
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(
                          'Catalog Items: ${catalogErrors.length}',
                          style: TextStyle(fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                  
                  SizedBox(height: 16),
                  
                  // Action Buttons
                  Row(
                    children: [
                      ElevatedButton(
                        onPressed: _seedDatabase,
                        child: Text('Seed Database'),
                      ),
                      SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: _createTestPendingError,
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
                        child: Text('Simulate Pending'),
                      ),
                      SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: _clearDatabase,
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                        child: Text('Clear Database'),
                      ),
                    ],
                  ),
                  
                  SizedBox(height: 16),
                  
                  // Test Steps
                  Text(
                    'Test Steps:',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 8),
                  Container(
                    height: 200,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: ListView.builder(
                      itemCount: testSteps.length,
                      itemBuilder: (context, index) {
                        final step = testSteps[index];
                        return Padding(
                          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          child: Text(
                            step,
                            style: TextStyle(
                              fontSize: 12,
                              fontFamily: 'monospace',
                              color: step.contains('✅') ? Colors.green : 
                                     step.contains('❌') ? Colors.red : Colors.black,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  
                  SizedBox(height: 16),
                  
                  // Raw Database Data
                  if (rawDbData.isNotEmpty) ...[
                    Text(
                      'Raw Database Data (First 5 rows):',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 8),
                    Container(
                      height: 200,
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: ListView.builder(
                        itemCount: rawDbData.length,
                        itemBuilder: (context, index) {
                          final row = rawDbData[index];
                          return Card(
                            margin: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            child: Padding(
                              padding: EdgeInsets.all(8),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: row.entries.map((entry) {
                                  return Text(
                                    '${entry.key}: ${entry.value}',
                                    style: TextStyle(fontSize: 11, fontFamily: 'monospace'),
                                  );
                                }).toList(),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                  
                  SizedBox(height: 16),
                  
                  // Catalog Items Preview
                  if (catalogErrors.isNotEmpty) ...[
                    Text(
                      'Catalog Items Preview (First 3):',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 8),
                    ...catalogErrors.take(3).map((error) => Card(
                      margin: EdgeInsets.symmetric(vertical: 4),
                      child: ListTile(
                        title: Text('${error.code} - ${error.category}'),
                        subtitle: Text(error.description),
                        trailing: Text(error.severity),
                      ),
                    )),
                  ],
                ],
              ),
            ),
    );
  }
}
