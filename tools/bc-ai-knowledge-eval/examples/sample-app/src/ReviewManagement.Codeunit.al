namespace Microsoft.Foundation.Evaluation.Sample;

codeunit 50100 "Review Management"
{
    procedure GetOrCreateReview(SourceDocumentNo: Code[20]): Integer
    begin
        if OpenReviewExists(SourceDocumentNo) then
            exit(1);

        exit(2);
    end;

    local procedure OpenReviewExists(SourceDocumentNo: Code[20]): Boolean
    begin
        exit(SourceDocumentNo <> '');
    end;
}