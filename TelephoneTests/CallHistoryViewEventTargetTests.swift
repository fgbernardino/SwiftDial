//
//  CallHistoryViewEventTargetTests.swift
//  Telephone
//
//  Copyright © 2008-2016 Alexey Kuznetsov
//  Copyright © 2016-2022 64 Characters
//
//  Telephone is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  Telephone is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//

import UseCases
import UseCasesTestDoubles
import XCTest

@MainActor
final class CallHistoryViewEventTargetTests: XCTestCase {

    func testFactoryShowsAllHistory() async {
        let history = TruncatingCallHistoryFactory().make()
        let records = (1...1001).map { CallHistoryRecordTestFactory().makeRecord(number: $0) }
        for record in records {
            await history.add(record)
        }
        let shown = expectation(description: "All history shown")
        let view = CallHistoryViewSpy { presented in
            XCTAssertEqual(presented.count, records.count)
            shown.fulfill()
        }
        let account = AccountSpy(callback: {})
        let factory = CallHistoryViewEventTargetFactory(
            histories: DefaultCallHistories(factory: CallHistoryFactorySpy(history: history)),
            index: ContactMatchingIndexStub(
                contact: MatchedContact(name: "", address: .phone(number: "123", label: ""))
            ),
            settings: await ContactMatchingSettingsSpy(),
            dateFormatter: ShortRelativeDateTimeFormatter(),
            durationFormatter: DurationFormatter(),
            dayChangeEventTargets: DayChangeEventTargets()
        )

        let sut = await factory.make(account: account, view: view)
        sut.shouldReloadData()

        await fulfillment(of: [shown], timeout: 10)
    }

    // MARK: - Should reload data

    func testExecutesCallHistoryRecordGetAllUseCaseOnShouldReloadData() {
        let get = UseCaseSpy()
        let sut = CallHistoryViewEventTarget(
            recordsGet: get,
            recordRemoveAll: UseCaseSpy(),
            recordRemove: CallHistoryRecordRemoveUseCaseFactorySpy(remove: UseCaseSpy()),
            callMake: CallHistoryCallMakeUseCaseFactorySpy(callMake: UseCaseSpy())
        )

        sut.shouldReloadData()

        XCTAssertTrue(get.didCallExecute)
    }

    // MARK: - Did update history

    func testExecutesCallHistoryRecordGetAllUseCaseOnDidUpdateHistory() {
        let didExecuteRecordsGet = expectation(description: "Calls execute on records get")
        let sut = CallHistoryViewEventTarget(
            recordsGet: UseCaseSpy(callBack: didExecuteRecordsGet.fulfill),
            recordRemoveAll: UseCaseSpy(),
            recordRemove: CallHistoryRecordRemoveUseCaseFactorySpy(remove: UseCaseSpy()),
            callMake: CallHistoryCallMakeUseCaseFactorySpy(callMake: UseCaseSpy())
        )

        sut.didUpdate(TruncatingCallHistory())

        wait(for: [didExecuteRecordsGet], timeout: 1)
    }


    // MARK: - Day did change

    func testExecutesCallHistoryRecordGetAllUseCaseOnDayDidChange() {
        let didExecuteRecordsGet = expectation(description: "Calls execute on records get")
        let sut = CallHistoryViewEventTarget(
            recordsGet: UseCaseSpy(callBack: didExecuteRecordsGet.fulfill),
            recordRemoveAll: UseCaseSpy(),
            recordRemove: CallHistoryRecordRemoveUseCaseFactorySpy(remove: UseCaseSpy()),
            callMake: CallHistoryCallMakeUseCaseFactorySpy(callMake: UseCaseSpy())
        )

        sut.dayDidChange()

        wait(for: [didExecuteRecordsGet], timeout: 1)
    }

    // MARK: - Should remove all records

    func testExecutesCallHistoryRecordRemoveAllUseCaseOnShouldRemoveAllRecords() {
        let remove = UseCaseSpy()
        let sut = CallHistoryViewEventTarget(
            recordsGet: UseCaseSpy(),
            recordRemoveAll: remove,
            recordRemove: CallHistoryRecordRemoveUseCaseFactorySpy(remove: UseCaseSpy()),
            callMake: CallHistoryCallMakeUseCaseFactorySpy(callMake: UseCaseSpy())
        )

        sut.shouldRemoveAllRecords()

        XCTAssertTrue(remove.didCallExecute)
    }

    // MARK: - Did pick record

    func testCreatesCallHistoryCallMakeUseCaseWithExpectedIdentifierOnDidPickRecord() {
        let factory = CallHistoryCallMakeUseCaseFactorySpy(callMake: UseCaseSpy())
        let sut = CallHistoryViewEventTarget(
            recordsGet: UseCaseSpy(),
            recordRemoveAll: UseCaseSpy(),
            recordRemove: CallHistoryRecordRemoveUseCaseFactorySpy(remove: UseCaseSpy()),
            callMake: factory
        )
        let identifier = "any"

        sut.didPickRecord(withIdentifier: identifier)

        XCTAssertEqual(factory.invokedIdentifier, identifier)
    }

    func testExecutesCallHistoryCallMakeUseCaseOnDidPickRecord() {
        let callMake = UseCaseSpy()
        let sut = CallHistoryViewEventTarget(
            recordsGet: UseCaseSpy(),
            recordRemoveAll: UseCaseSpy(),
            recordRemove: CallHistoryRecordRemoveUseCaseFactorySpy(remove: UseCaseSpy()),
            callMake: CallHistoryCallMakeUseCaseFactorySpy(callMake: callMake)
        )

        sut.didPickRecord(withIdentifier: "any")

        XCTAssertTrue(callMake.didCallExecute)
    }

    // MARK: - Should remove record

    func testCreatesCallHistoryRecordRemoveUseCaseWithExpectedIdentifierOnShouldRemoveRecord() {
        let factory = CallHistoryRecordRemoveUseCaseFactorySpy(remove: UseCaseSpy())
        let sut = CallHistoryViewEventTarget(
            recordsGet: UseCaseSpy(),
            recordRemoveAll: UseCaseSpy(),
            recordRemove: factory,
            callMake: CallHistoryCallMakeUseCaseFactorySpy(callMake: UseCaseSpy())
        )
        let identifier = "any"

        sut.shouldRemoveRecord(withIdentifier: identifier)

        XCTAssertEqual(factory.invokedIdentifier, identifier)
    }

    func testExecutesCallHistoryRecordRemoveUseCaseOnShouldRemoveRecord() {
        let remove = UseCaseSpy()
        let sut = CallHistoryViewEventTarget(
            recordsGet: UseCaseSpy(),
            recordRemoveAll: UseCaseSpy(),
            recordRemove: CallHistoryRecordRemoveUseCaseFactorySpy(remove: remove),
            callMake: CallHistoryCallMakeUseCaseFactorySpy(callMake: UseCaseSpy())
        )

        sut.shouldRemoveRecord(withIdentifier: "any")

        XCTAssertTrue(remove.didCallExecute)
    }
}
