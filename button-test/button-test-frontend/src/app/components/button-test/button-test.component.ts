import { ChangeDetectionStrategy, ChangeDetectorRef, Component, Input, OnChanges, SimpleChanges } from '@angular/core';
import { TranslateService } from '@ngx-translate/core';
import { ProgramPresenter, ProgramPresenterAPI, RobotSettings } from '@universal-robots/contribution-api';
import { ButtonTestNode } from './button-test.node';
import { first } from 'rxjs/operators';

@Component({
    templateUrl: './button-test.component.html',
    styleUrls: ['./button-test.component.scss'],
    changeDetection: ChangeDetectionStrategy.OnPush,
    standalone: false
})

export class ButtonTestComponent implements OnChanges, ProgramPresenter {
    // presenterAPI is optional
    @Input() presenterAPI: ProgramPresenterAPI;

    // robotSettings is optional
    @Input() robotSettings: RobotSettings;
    // contributedNode is optional
    @Input() contributedNode: ButtonTestNode;

    labelText = "I\'m some text! :3";
    debugOffText = "Debug: off";
    debugOnText = "Debug: on";
    debugLabelText = this.debugOffText

    debugModeOn = false;

    constructor(
        protected readonly translateService: TranslateService,
        protected readonly cd: ChangeDetectorRef
    ) {
    }

    ngOnChanges(changes: SimpleChanges): void {
        if (changes?.robotSettings) {
            if (!changes?.robotSettings?.currentValue) {
                return;
            }

            if (changes?.robotSettings?.isFirstChange()) {
                if (changes?.robotSettings?.currentValue) {
                    this.translateService.use(changes?.robotSettings?.currentValue?.language);
                }
                this.translateService.setDefaultLang('en');
            }

            this.translateService
                .use(changes?.robotSettings?.currentValue?.language)
                .pipe(first())
                .subscribe(() => {
                    this.cd.detectChanges();
                });
        }
    }

    onClicked(){
        if (this.debugModeOn){
            console.log("Clicked!");
        }
        const now = new Date();
        const hour = now.getHours() + 1;
        const minute = now.getMinutes() + 1;
        const second = now.getSeconds() +1;
        const readableTime = hour.toString() + ":" + minute.toString() + ":" + second.toString();
        this.labelText = "The time is: " + readableTime;
    }
    debugOnClicked(){
        if (this.debugModeOn){
            this.debugModeOn = false;
            this.debugLabelText = this.debugOffText;
        } else{
            this.debugModeOn = true;
            this.debugLabelText = this.debugOnText;
        }
    }

    // call saveNode to save node parameters
    async saveNode() {
        this.cd.detectChanges();
        await this.presenterAPI.programNodeService.updateNode(this.contributedNode);
    }
}
