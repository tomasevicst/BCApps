namespace Sample.Dependency;

codeunit 99992 "Sample Shared Policy"
{
    procedure IsReusable(Status: Text): Boolean
    begin
        exit(Status = 'Open');
    end;
}