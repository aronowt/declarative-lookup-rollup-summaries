@isTest(seeAllData=true)
public class CustomRollupTest {
    
    /*  @testSetup
static void setup() {
Account acct = new Account(Name = 'test account');
insert acct;
Case cas = new Case(AccountId = acct.Id);
insert cas;
}*/
    
    @isTest
    static void initAndCheckRollupTest() {
        Account acct = new Account(Name = 'test account');
        insert acct;
        Case cas = new Case(AccountId = acct.Id);
        insert cas;
        
        Test.startTest();
        CustomRollup.initAndCheckRollup();
        Test.stopTest();
    }
    
    
    
}